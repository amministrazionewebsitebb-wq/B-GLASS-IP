import Foundation

/// Measures the line (ping, jitter, download, upload against a public server) and, apart, how the provider answers.
public struct SpeedResult: Sendable {
    public var pingMs = 0.0
    public var jitterMs = 0.0
    public var downMbps = 0.0
    public var upMbps = 0.0
    public var panelMs: Double?                // time the provider's panel took to answer
    public var streamMbps: Double?             // speed of a sample of the provider's films
    public var server = ""

    /// The slowest of what matters: the line, and the provider when it was measured.
    public var effectiveMbps: Double {
        guard let s = streamMbps else { return downMbps }
        return min(downMbps, s)
    }

    public enum Grade: String, Sendable { case excellent = "Ottima", good = "Buona", fair = "Sufficiente", poor = "Scarsa", bad = "Insufficiente" }

    public var grade: Grade {
        switch effectiveMbps {
        case 40...: return .excellent
        case 20...: return .good
        case 9...: return .fair
        case 3.5...: return .poor
        default: return .bad
        }
    }

    /// Formats the connection can carry with some margin (bitrates of typical IPTV streams).
    public var formats: [String] {
        let m = effectiveMbps
        var f: [String] = []
        if m >= 4 { f.append("SD") }
        if m >= 8 { f.append("HD") }
        if m >= 15 { f.append("Full HD") }
        if m >= 35 { f.append("4K") }
        return f
    }

    public var advice: [String] {
        var a: [String] = []
        if downMbps < 8 { a.append("La linea è lenta: avvicinati al router o prova un cavo/Wi-Fi a 5 GHz.") }
        if jitterMs > 30 { a.append("La rete è instabile (variazione alta): i canali possono bloccarsi.") }
        if pingMs > 120 { a.append("Il tempo di risposta è alto: con una VPN o un Wi-Fi debole i canali partono lentamente.") }
        if let s = streamMbps, downMbps > 0, s < downMbps * 0.4 { a.append("Il fornitore consegna meno di quanto offre la tua linea: il limite è lato server.") }
        if a.isEmpty { a.append("Tutto a posto per guardare i canali in diretta e i film.") }
        return a
    }
}

public final class SpeedTest {
    public enum Stage: String, Sendable { case ping = "Tempo di risposta", download = "Download", upload = "Upload", provider = "Il tuo fornitore" }

    private let primary = "https://speed.cloudflare.com"
    private let fallback = "https://speedtest.tele2.net"
    private var cancelled = false
    private let lock = NSLock()

    public init() {}

    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || Task.isCancelled }

    /// `progress`: the stage and a live value (ms for ping, Mbit/s for the rest).
    public func run(provider: Source?, measureStream: Bool, backend: Backend?, progress: @escaping (Stage, Double) -> Void) async -> SpeedResult {
        var r = SpeedResult()
        r.server = "Cloudflare"
        // 1. ping and jitter
        var times: [Double] = []
        for _ in 0..<6 {
            if isCancelled { return r }
            let t0 = Date()
            var req = URLRequest(url: URL(string: "\(primary)/__down?bytes=0")!)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 6
            if (try? await URLSession.shared.data(for: req)) != nil {
                let ms = Date().timeIntervalSince(t0) * 1000
                times.append(ms)
                progress(.ping, ms)
            }
        }
        if times.count > 1 {
            let t = Array(times.dropFirst())                                  // the first one pays for the connection set-up
            r.pingMs = t.min() ?? 0
            var d = 0.0
            for i in 1..<t.count { d += abs(t[i] - t[i - 1]) }
            r.jitterMs = t.count > 1 ? d / Double(t.count - 1) : 0
        } else if let f = times.first { r.pingMs = f }
        if times.isEmpty {                                                    // Cloudflare unreachable: use the fallback host
            r.server = "Tele2"
        }
        // 2. download: four parallel streams for a few seconds
        let base = times.isEmpty ? fallback : primary
        let downURL = base == primary ? "\(primary)/__down?bytes=100000000" : "\(fallback)/100MB.zip"
        r.downMbps = await measureDownload(urls: Array(repeating: downURL, count: 4), seconds: 7) { progress(.download, $0) }
        if isCancelled { return r }
        // 3. upload
        if base == primary { r.upMbps = await measureUpload(url: "\(primary)/__up", megabytes: 6) { progress(.upload, $0) } }
        if isCancelled { return r }
        // 4. the provider
        if let s = provider {
            let t0 = Date()
            if s.type == .xtream, (try? await XtreamClient(s).auth()) != nil {
                r.panelMs = Date().timeIntervalSince(t0) * 1000
                progress(.provider, r.panelMs ?? 0)
            }
            if measureStream, let b = backend, let url = sampleURL(for: s, backend: b) {
                r.streamMbps = await measureDownload(urls: [url], seconds: 6, ua: s.ua, rangeBytes: 60_000_000) { progress(.provider, $0) }
            }
        }
        return r
    }

    private func sampleURL(for s: Source, backend: Backend) -> String? {
        guard let it = backend.lib.snap.items.first(where: { $0.src == s.id && $0.kind == .movie }) else { return nil }
        if let u = it.url { return u }
        guard s.type == .xtream, let sid = it.sid else { return nil }
        return XtreamClient(s).movieUrl(sid, ext: it.ext)
    }

    // MARK: measuring

    private final class Counter: NSObject, URLSessionDataDelegate {
        private let lock = NSLock()
        private var bytes: Int64 = 0
        var total: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock(); bytes += Int64(data.count); lock.unlock()
        }
    }

    private func measureDownload(urls: [String], seconds: Double, ua: String = "", rangeBytes: Int? = nil, live: @escaping (Double) -> Void) async -> Double {
        let counter = Counter()
        let cfg = Net.configuration()
        cfg.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: cfg, delegate: counter, delegateQueue: nil)
        var tasks: [URLSessionDataTask] = []
        for u in urls {
            guard var req = try? Net.request(u, ua: ua) else { continue }
            if let n = rangeBytes { req.setValue("bytes=0-\(n)", forHTTPHeaderField: "Range") }
            let t = session.dataTask(with: req)
            tasks.append(t)
            t.resume()
        }
        let t0 = Date()
        var last: (Date, Int64) = (t0, 0)
        var warm: (Date, Int64)?
        while Date().timeIntervalSince(t0) < seconds && !isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let now = Date(), b = counter.total
            if warm == nil && now.timeIntervalSince(t0) > 1.0 { warm = (now, b) }          // the first second is ramp-up
            let dt = now.timeIntervalSince(last.0)
            if dt > 0 { live(Double(b - last.1) * 8 / dt / 1_000_000) }
            last = (now, b)
        }
        let end = Date(), total = counter.total
        tasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
        if let w = warm, end.timeIntervalSince(w.0) > 0.5 { return Double(total - w.1) * 8 / end.timeIntervalSince(w.0) / 1_000_000 }
        let dt = end.timeIntervalSince(t0)
        return dt > 0 ? Double(total) * 8 / dt / 1_000_000 : 0
    }

    private final class UploadMeter: NSObject, URLSessionTaskDelegate {
        private let lock = NSLock()
        private var sent: Int64 = 0
        var total: Int64 { lock.lock(); defer { lock.unlock() }; return sent }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            lock.lock(); sent = totalBytesSent; lock.unlock()
        }
    }

    private func measureUpload(url: String, megabytes: Int, live: @escaping (Double) -> Void) async -> Double {
        guard let u = URL(string: url) else { return 0 }
        let meter = UploadMeter()
        let session = URLSession(configuration: Net.configuration(), delegate: meter, delegateQueue: nil)
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        let body = Data(count: megabytes * 1_000_000)
        let t0 = Date()
        let task = session.uploadTask(with: req, from: body) { _, _, _ in }
        task.resume()
        var last: (Date, Int64) = (t0, 0)
        while task.state == .running && Date().timeIntervalSince(t0) < 12 && !isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let now = Date(), b = meter.total
            let dt = now.timeIntervalSince(last.0)
            if dt > 0 { live(Double(b - last.1) * 8 / dt / 1_000_000) }
            last = (now, b)
        }
        let dt = Date().timeIntervalSince(t0)
        let total = meter.total
        task.cancel()
        session.invalidateAndCancel()
        return dt > 0 ? Double(total) * 8 / dt / 1_000_000 : 0
    }
}
