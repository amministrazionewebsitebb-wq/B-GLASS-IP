import Foundation
import Network

/// A minimal HTTP/1.1 server on localhost, enough to play the part of an Xtream panel or a playlist host in the checks.
final class TestServer {
    struct Response {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        init(_ body: Data, status: Int = 200, headers: [String: String] = [:]) { self.body = body; self.status = status; self.headers = headers }
        init(_ text: String, status: Int = 200, headers: [String: String] = [:]) { self.init(Data(text.utf8), status: status, headers: headers) }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "testserver")
    private let handler: (_ path: String, _ query: [String: String], _ headers: [String: String]) -> Response
    private(set) var requests: [String] = []
    private let lock = NSLock()
    private(set) var port: UInt16 = 0

    convenience init(handler: @escaping (_ path: String, _ query: [String: String]) -> Response) throws {
        try self.init(withHeaders: { p, q, _ in handler(p, q) })
    }

    /// `headers`: the request headers, names in lower case.
    init(withHeaders handler: @escaping (_ path: String, _ query: [String: String], _ headers: [String: String]) -> Response) throws {
        self.handler = handler
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] st in
            if case .ready = st { self?.port = self?.listener.port?.rawValue ?? 0; ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
    }

    var base: String { "http://127.0.0.1:\(port)" }

    var requestLog: [String] { lock.lock(); defer { lock.unlock() }; return requests }

    func stop() { listener.cancel() }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        read(c, Data())
    }

    private func read(_ c: NWConnection, _ acc: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self else { return }
            var buf = acc
            if let d = data { buf.append(d) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[buf.startIndex..<end.lowerBound], as: UTF8.self)
                self.respond(c, head)
            } else if done || err != nil { c.cancel() }
            else { self.read(c, buf) }
        }
    }

    private func respond(_ c: NWConnection, _ head: String) {
        let first = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        let target = parts.count > 1 ? String(parts[1]) : "/"
        lock.lock(); requests.append(target); lock.unlock()
        var path = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            for kv in target[target.index(after: q)...].split(separator: "&") {
                let p = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                query[String(p[0])] = p.count > 1 ? (String(p[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(p[1])) : ""
            }
        }
        var headers: [String: String] = [:]
        for l in head.split(separator: "\r\n").dropFirst() {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[l.startIndex..<c].lowercased()] = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces)
        }
        let r = handler(path, query, headers)
        var out = "HTTP/1.1 \(r.status) \(r.status == 200 ? "OK" : "ERR")\r\nContent-Length: \(r.body.count)\r\nConnection: close\r\n"
        for (k, v) in r.headers { out += "\(k): \(v)\r\n" }
        out += "\r\n"
        var data = Data(out.utf8)
        data.append(r.body)
        c.send(content: data, completion: .contentProcessed { _ in c.cancel() })
    }
}

/// gzip through the system tool (the checks must not depend on the code being tested to produce test input).
func gzipped(_ data: Data) -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    p.arguments = ["-c", "-n"]
    let i = Pipe(), o = Pipe()
    p.standardInput = i
    p.standardOutput = o
    try? p.run()
    DispatchQueue.global().async { i.fileHandleForWriting.write(data); try? i.fileHandleForWriting.close() }
    let out = o.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return out
}
