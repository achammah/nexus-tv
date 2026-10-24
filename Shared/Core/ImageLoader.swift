import Foundation
import CoreGraphics
import ImageIO

/// One picture loader for the Mac and the Apple TV.
/// - one request per picture, however many tiles ask at once;
/// - its own session: 64 MB memory + 512 MB disk cache, 15 s timeout, 8 connections per host;
/// - the picture is cut down to the tile size with ImageIO, off the main thread;
/// - a failure is tried once more after 2 s, then remembered for at most 60 s;
/// - a host that does not answer (timeout, no connection) is marked down for 60 s: the other pictures
///   of that host fail at once instead of each waiting for its own timeout.
/// Debug launch flag `-NXImageLog YES` (with `-NXMetrics YES`) writes one line per request to the metrics log.
final class CGImageBox { let image: CGImage; init(_ i: CGImage) { image = i } }

actor ImageLoader {
    static let shared = ImageLoader()
    static let logOn = UserDefaults.standard.bool(forKey: "NXImageLog")

    struct Settings {
        var retryDelay: Duration = .seconds(2)
        var failureTTL: TimeInterval = 60
        var hostDownTTL: TimeInterval = 60
        var perHost = 8
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 6
        c.httpMaximumConnectionsPerHost = 8
        return c
    }

    private let session: URLSession
    private let settings: Settings
    /// Decoded pictures; NSCache is thread-safe, so the views read it without waiting for the actor.
    private nonisolated let cache = NSCache<NSString, CGImageBox>()
    private var inflightData: [URL: Task<Data?, Never>] = [:]
    private var inflightImage: [String: Task<CGImage?, Never>] = [:]
    private var failedAt: [URL: Date] = [:]
    private var hostDownAt: [String: Date] = [:]
    private var slotsUsed: [String: Int] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    /// Network requests started (tests count them).
    private(set) var requestCount = 0

    init(configuration: URLSessionConfiguration = ImageLoader.makeConfiguration(), settings: Settings = Settings()) {
        session = URLSession(configuration: configuration)
        self.settings = settings
        cache.countLimit = 800
        cache.totalCostLimit = 160 << 20
    }

    static func bucket(_ maxPixel: CGFloat) -> Int { max(100, Int((maxPixel / 100).rounded(.up)) * 100) }
    private nonisolated func key(_ url: URL, _ maxPixel: CGFloat) -> NSString { "\(url.absoluteString)#\(Self.bucket(maxPixel))" as NSString }

    /// A picture already decoded, if any (no waiting, safe from any thread).
    nonisolated func cached(_ url: URL, maxPixel: CGFloat) -> CGImage? { cache.object(forKey: key(url, maxPixel))?.image }

    func image(_ url: URL, maxPixel: CGFloat) async -> CGImage? {
        let k = key(url, maxPixel)
        if let c = cache.object(forKey: k) { return c.image }
        if let t = failedAt[url] {
            if Date().timeIntervalSince(t) < settings.failureTTL { return nil }
            failedAt[url] = nil
        }
        let ks = k as String
        if let t = inflightImage[ks] { return await t.value }
        let px = CGFloat(Self.bucket(maxPixel))
        let t = Task<CGImage?, Never> {
            guard let data = await self.data(url) else { return nil }
            let cg = await Task.detached(priority: .userInitiated) { ImageLoader.downsample(data, maxPixel: px) }.value
            if let cg {
                self.cache.setObject(CGImageBox(cg), forKey: k, cost: cg.width * cg.height * 4)
            } else {
                self.failedAt[url] = Date()
                self.log(url, "undecodable bytes=\(data.count)", 0)
            }
            return cg
        }
        inflightImage[ks] = t
        let r = await t.value
        inflightImage[ks] = nil
        return r
    }

    // MARK: network

    /// The bytes of one URL: one request however many callers; one retry; failures remembered.
    private func data(_ url: URL) async -> Data? {
        if let t = inflightData[url] { return await t.value }
        let t = Task<Data?, Never> {
            var d = await self.attempt(url)
            if d == nil, !self.isDown(url.host ?? "") {
                try? await Task.sleep(for: self.settings.retryDelay)
                d = await self.attempt(url)
            }
            if d == nil { self.failedAt[url] = Date() }
            return d
        }
        inflightData[url] = t
        let r = await t.value
        inflightData[url] = nil
        return r
    }

    private func isDown(_ host: String) -> Bool {
        guard let t = hostDownAt[host] else { return false }
        if Date().timeIntervalSince(t) < settings.hostDownTTL { return true }
        hostDownAt[host] = nil
        return false
    }

    private func acquire(_ host: String) async {
        if slotsUsed[host, default: 0] < settings.perHost { slotsUsed[host, default: 0] += 1; return }
        await withCheckedContinuation { waiters[host, default: []].append($0) }
    }
    private func release(_ host: String) {
        if var w = waiters[host], !w.isEmpty {
            let next = w.removeFirst(); waiters[host] = w; next.resume()      // the slot passes to the next one
        } else { slotsUsed[host, default: 1] -= 1 }
    }

    private func attempt(_ url: URL) async -> Data? {
        let host = url.host ?? ""
        await acquire(host)
        defer { release(host) }
        if isDown(host) { log(url, "host-down", 0); return nil }
        requestCount += 1
        let t0 = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(t0) * 1000) }
        do {
            let (d, r) = try await session.data(from: url)
            let code = (r as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(code), !d.isEmpty else { log(url, "status=\(code)", ms()); return nil }
            log(url, "status=\(code) bytes=\(d.count)", ms())
            return d
        } catch {
            let code = (error as NSError).code
            if [NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost].contains(code) {
                hostDownAt[host] = Date()
            }
            log(url, "error=\(code)", ms())
            return nil
        }
    }

    private nonisolated func log(_ url: URL, _ what: String, _ ms: Int) {
        #if DEBUG
        guard Self.logOn else { return }
        // host and file name only: a provider URL can carry the login
        Metrics.shared.mark("img \(what) \(ms)ms \(url.scheme ?? "")://\(url.host ?? "")/\(url.lastPathComponent)")
        #endif
    }

    // MARK: decode

    /// Cut to `maxPixel` on the longer side (never enlarged) and drawn once, so the main thread never decodes it.
    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let cg: CGImage?
        if max(w, h) > Double(maxPixel) {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        } else {
            cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        guard let cg else { return nil }
        let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx?.makeImage() ?? cg
    }
}
