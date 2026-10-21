import Compression
import Foundation

public enum NetError: Error, LocalizedError {
    case http(Int)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .http(let c): return "HTTP \(c)"
        case .invalid(let m): return m
        }
    }
}

/// Shared HTTP plumbing: IPTV friendly defaults, optional lenient TLS, downloads to a file (un-gzipped when needed).
public enum Net {
    public static let defaultUA = "VLC/3.0.20 LibVLC/3.0.20"

    private final class TrustAll: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: t))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    public static func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 3600
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 4
        return c
    }

    private static let lock = NSLock()
    private static var secureSession: URLSession?
    private static var looseSession: URLSession?

    /// One URLSession per TLS mode, for small requests.
    static func session(insecure: Bool) -> URLSession {
        lock.lock(); defer { lock.unlock() }
        if insecure {
            if looseSession == nil { looseSession = URLSession(configuration: configuration(), delegate: TrustAll(), delegateQueue: nil) }
            return looseSession!
        }
        if secureSession == nil { secureSession = URLSession(configuration: configuration()) }
        return secureSession!
    }

    public static func request(_ url: String, ua: String) throws -> URLRequest {
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(CharacterSet(charactersIn: "#%")) ) ?? ""),
              u.scheme != nil else { throw NetError.invalid("Indirizzo non valido") }
        var r = URLRequest(url: u)
        r.setValue(ua.isEmpty ? defaultUA : ua, forHTTPHeaderField: "User-Agent")
        r.setValue("*/*", forHTTPHeaderField: "Accept")
        return r
    }

    /// A small payload (JSON of an API call). Un-gzipped when it is a raw gzip body.
    public static func data(_ url: String, ua: String = "", insecure: Bool = false) async throws -> Data {
        let (d, resp) = try await session(insecure: insecure).data(for: try request(url, ua: ua))
        if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) { throw NetError.http(h.statusCode) }
        if Gzip.isGzip(d) { return try Gzip.inflate(d) }
        return d
    }

    /// The first bytes of a resource, without downloading the rest (checks that a playlist link answers).
    public static func peek(_ url: String, ua: String = "", insecure: Bool = false, bytes n: Int = 512) async throws -> Data {
        let (stream, resp) = try await session(insecure: insecure).bytes(for: try request(url, ua: ua))
        if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) { throw NetError.http(h.statusCode) }
        var out = Data()
        for try await b in stream {
            out.append(b)
            if out.count >= n { break }
        }
        return out
    }

    public static func string(_ url: String, ua: String = "", insecure: Bool = false) async throws -> String {
        String(decoding: try await data(url, ua: ua, insecure: insecure), as: UTF8.self)
    }

    /// Downloads to a temporary file (un-gzipped when the payload starts with the gzip magic bytes). The caller deletes it.
    /// `progress` gets (bytes so far, bytes expected or -1).
    public static func download(_ url: String, ua: String = "", insecure: Bool = false, progress: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        let req = try request(url, ua: ua)
        let job = DownloadJob(insecure: insecure, progress: progress)
        let raw = try await job.run(req)
        if Gzip.fileIsGzip(raw) {
            defer { try? FileManager.default.removeItem(at: raw) }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("bglass-\(UUID().uuidString).dat")
            do { try Gzip.inflateFile(from: raw, to: out) } catch { try? FileManager.default.removeItem(at: out); throw error }
            return out
        }
        return raw
    }

    /// Maps a failure to something a person can act on (Italian, like the rest of the UI).
    public static func explain(_ error: Error) -> String {
        if error is CancellationError { return "Operazione annullata" }
        if let n = error as? NetError {
            switch n {
            case .http(let c):
                if c == 401 || c == 403 { return "Accesso negato dal server (HTTP \(c)). Controlla utente, password o User-Agent." }
                if c == 404 { return "Indirizzo non trovato (404). Controlla il link." }
                if c >= 500 { return "Il server ha un problema (HTTP \(c)). Riprova più tardi." }
                return "Errore del server (HTTP \(c))."
            case .invalid(let m): return m
            }
        }
        if let u = error as? URLError {
            switch u.code {
            case .cannotFindHost, .dnsLookupFailed: return "Server non trovato. Controlla l'indirizzo e la connessione a Internet."
            case .timedOut: return "Il server non risponde (tempo scaduto). Riprova tra poco."
            case .cannotConnectToHost, .networkConnectionLost: return "Impossibile connettersi al server. Controlla indirizzo e porta."
            case .notConnectedToInternet: return "Nessuna connessione a Internet."
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed, .clientCertificateRejected:
                return "Errore del certificato HTTPS. Prova ad attivare \"Ignora errori del certificato\" nelle opzioni avanzate."
            case .cancelled: return "Operazione annullata"
            case .appTransportSecurityRequiresSecureConnection: return "Il sistema blocca le connessioni non protette."
            default: break
            }
        }
        let m = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return m.isEmpty ? String(describing: error) : m
    }
}

/// One download task with progress, a file that survives the delegate callback, and cancellation.
private final class DownloadJob: NSObject, URLSessionDownloadDelegate, URLSessionDelegate {
    private let insecure: Bool
    private let progress: ((Int64, Int64) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cont: CheckedContinuation<URL, Error>?
    private let lock = NSLock()
    private var finished = false

    init(insecure: Bool, progress: ((Int64, Int64) -> Void)?) {
        self.insecure = insecure
        self.progress = progress
    }

    func run(_ req: URLRequest) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                lock.lock()
                cont = c
                let s = URLSession(configuration: Net.configuration(), delegate: self, delegateQueue: nil)
                session = s
                let t = s.downloadTask(with: req)
                task = t
                lock.unlock()
                if Task.isCancelled { finish(.failure(CancellationError())); return }
                t.resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ r: Result<URL, Error>) {
        lock.lock()
        if finished { lock.unlock(); if case .success(let u) = r { try? FileManager.default.removeItem(at: u) }; return }
        finished = true
        let c = cont
        cont = nil
        let t = task, s = session
        lock.unlock()
        t?.cancel()
        s?.finishTasksAndInvalidate()
        switch r {
        case .success(let u): c?.resume(returning: u)
        case .failure(let e): c?.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let h = downloadTask.response as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
            finish(.failure(NetError.http(h.statusCode)))
            return
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bglass-\(UUID().uuidString).dl")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            finish(.success(dest))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error { finish(.failure(e)) }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if insecure, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: t))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// gzip support on top of the Compression framework (which decodes the raw DEFLATE stream inside the gzip wrapper).
public enum Gzip {
    public static func isGzip(_ d: Data) -> Bool { d.count > 2 && d[d.startIndex] == 0x1f && d[d.startIndex + 1] == 0x8b }

    public static func fileIsGzip(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 2), d.count == 2 else { return false }
        return d[d.startIndex] == 0x1f && d[d.startIndex + 1] == 0x8b
    }

    /// Length of the gzip header (fixed part plus the optional extra, name, comment and header CRC), or nil when the data is not gzip.
    static func headerLength(_ d: Data) -> Int? {
        let b = [UInt8](d.prefix(4096))
        guard b.count >= 10, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var p = 10
        if flags & 4 != 0 {
            guard p + 2 <= b.count else { return nil }
            p += 2 + Int(b[p]) + (Int(b[p + 1]) << 8)
        }
        for bit: UInt8 in [8, 16] where flags & bit != 0 {
            while p < b.count && b[p] != 0 { p += 1 }
            p += 1
        }
        if flags & 2 != 0 { p += 2 }
        return p <= b.count ? p : nil
    }

    private final class Sink {
        var out = Data()
        var handle: FileHandle?
        func write(_ p: UnsafePointer<UInt8>, _ n: Int) {
            if let h = handle { h.write(Data(bytes: p, count: n)) } else { out.append(p, count: n) }
        }
    }

    private static func inflate(chunks next: () throws -> Data?, sink: Sink) throws {
        let bufSize = 1 << 16
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { dst.deallocate() }
        var stream = compression_stream(dst_ptr: dst, dst_size: bufSize, src_ptr: UnsafePointer(dst), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw NetError.invalid("Impossibile decomprimere i dati")
        }
        defer { compression_stream_destroy(&stream) }
        var done = false
        while !done {
            let input = try next()
            let last = input == nil
            let bytes = input ?? Data()
            try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let base = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(dst)
                stream.src_ptr = base
                stream.src_size = raw.count
                while true {
                    stream.dst_ptr = dst
                    stream.dst_size = bufSize
                    let status = compression_stream_process(&stream, last ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    let produced = bufSize - stream.dst_size
                    if produced > 0 { sink.write(dst, produced) }
                    if status == COMPRESSION_STATUS_END { done = true; return }
                    if status == COMPRESSION_STATUS_ERROR { throw NetError.invalid("Dati compressi non validi") }
                    if stream.src_size == 0 && stream.dst_size != 0 { break }
                    if last && produced == 0 { done = true; return }                       // truncated input: keep what was decoded
                }
            }
            if last { done = true }
        }
    }

    public static func inflate(_ d: Data) throws -> Data {
        guard let start = headerLength(d) else { throw NetError.invalid("Dati compressi non validi") }
        let sink = Sink()
        var sent = false
        try inflate(chunks: {
            if sent { return nil }
            sent = true
            return d.subdata(in: (d.startIndex + start)..<d.endIndex)
        }, sink: sink)
        return sink.out
    }

    public static func inflateFile(from src: URL, to dst: URL) throws {
        let inH = try FileHandle(forReadingFrom: src)
        defer { try? inH.close() }
        let first = try inH.read(upToCount: 1 << 16) ?? Data()
        guard let start = headerLength(first) else { throw NetError.invalid("Dati compressi non validi") }
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let outH = try FileHandle(forWritingTo: dst)
        defer { try? outH.close() }
        let sink = Sink()
        sink.handle = outH
        var pending: Data? = first.subdata(in: (first.startIndex + start)..<first.endIndex)
        try inflate(chunks: {
            if let p = pending { pending = nil; if !p.isEmpty { return p } }
            let n = try inH.read(upToCount: 1 << 16) ?? Data()
            return n.isEmpty ? nil : n
        }, sink: sink)
    }
}
