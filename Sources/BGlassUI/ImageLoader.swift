import BGlassCore
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Posters and logos: downloaded once, kept on disk, decoded at the size the screen needs (providers often send 2000x3000 JPEGs),
/// and held in memory only while they are in use. Nothing here blocks the UI.
public final class ImageLoader {
    public static let shared = ImageLoader()

    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }

    private let memory = NSCache<NSString, Box>()
    private let session: URLSession
    private let limiter = AsyncLimiter(6)
    private let dir: URL

    private init() {
        let c = Net.configuration()
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: c)
        memory.totalCostLimit = 90 * 1024 * 1024
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("bglass-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.global(qos: .utility).async { [dir] in ImageLoader.trim(dir, limit: 400 * 1024 * 1024) }
    }

    /// Lets go of the decoded images (the files stay): called when the system is short of memory.
    public func dropMemory() { memory.removeAllObjects() }

    public func image(for urlString: String, maxPixel: Int) async -> CGImage? {
        let key = "\(maxPixel)|\(urlString)" as NSString
        if let b = memory.object(forKey: key) { return b.image }
        let file = dir.appendingPathComponent(Hash.fnv(urlString))
        var data: Data? = try? Data(contentsOf: file, options: .mappedIfSafe)
        if data == nil {
            guard let url = URL(string: urlString) ?? URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { return nil }
            await limiter.acquire()
            defer { Task { await limiter.release() } }
            if Task.isCancelled { return nil }
            var req = URLRequest(url: url)
            req.setValue(Net.defaultUA, forHTTPHeaderField: "User-Agent")
            guard let (d, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true, !d.isEmpty else { return nil }
            data = d
            try? d.write(to: file, options: .atomic)
        }
        guard let d = data, let img = ImageLoader.downsample(d, maxPixel: maxPixel) else { return nil }
        memory.setObject(Box(img), forKey: key, cost: img.width * img.height * 4)
        return img
    }

    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Deletes the oldest files when the cache grows past `limit` bytes.
    static func trim(_ dir: URL, limit: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var items = files.compactMap { u -> (URL, Date, Int)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }
        var total = items.reduce(0) { $0 + $1.2 }
        if total <= limit { return }
        items.sort { $0.1 < $1.1 }
        for it in items where total > limit * 3 / 4 {
            try? FileManager.default.removeItem(at: it.0)
            total -= it.2
        }
    }

    public func clearDisk() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func diskBytes() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

actor AsyncLimiter {
    private var running = 0
    private let max: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ max: Int) { self.max = max }

    func acquire() async {
        if running < max { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}

/// A remote picture with a coloured, titled placeholder behind it (also shown when the provider has no artwork or the link is dead).
public struct RemoteImage: View {
    let url: String?
    let maxPixel: Int
    let contentMode: ContentMode
    let title: String
    @State private var image: CGImage?

    public init(_ url: String?, title: String = "", maxPixel: Int = 400, contentMode: ContentMode = .fill) {
        self.url = url; self.title = title; self.maxPixel = maxPixel; self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if image == nil { Placeholder(title: title) }
            if let image = image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            image = nil
            guard let u = url, !u.isEmpty else { return }
            let img = await ImageLoader.shared.image(for: u, maxPixel: maxPixel)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) { image = img }
        }
    }
}

struct Placeholder: View {
    let title: String
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: Theme.placeholderColors(title), startPoint: .topLeading, endPoint: .bottomTrailing)
                if !title.isEmpty {
                    Text(Backend.cleanTitle(title))
                        .font(.system(size: max(10, min(g.size.width / 7.5, 20)), weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                        .minimumScaleFactor(0.6)
                        .padding(8)
                }
            }
        }
    }
}
