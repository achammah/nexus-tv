import XCTest
import AppKit
@testable import NexusTVMac

/// A URLProtocol stub: no network. `handler` answers each request; `hits` counts them per URL.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data)?)?      // nil = fail with `failure`
    nonisolated(unsafe) static var failure = NSURLErrorTimedOut
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    private static let lock = NSLock()
    static func reset() { lock.lock(); hits = [:]; lock.unlock() }
    static func count(_ s: String) -> Int { lock.lock(); defer { lock.unlock() }; return hits[s, default: 0] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.hits[request.url!.absoluteString, default: 0] += 1; Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            if let (code, data) = Self.handler?(self.request) {
                let r = HTTPURLResponse(url: self.request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } else {
                self.client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: Self.failure))
            }
        }
    }
    override func stopLoading() {}
}

final class ImageLoaderTests: XCTestCase {
    static func png(_ side: Int = 64) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
    private func loader(retry: Duration = .milliseconds(80), failureTTL: TimeInterval = 60, hostDownTTL: TimeInterval = 60) -> ImageLoader {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        return ImageLoader(configuration: c, settings: .init(retryDelay: retry, failureTTL: failureTTL, hostDownTTL: hostDownTTL, perHost: 8))
    }

    func testConcurrentRequestsForOneURLShareOneFetch() async {
        let data = Self.png()
        StubProtocol.handler = { _ in (200, data) }
        let l = loader()
        let u = URL(string: "http://logos.test/a.png")!
        let results = await withTaskGroup(of: CGImage?.self) { g -> [CGImage?] in
            for _ in 0..<20 { g.addTask { await l.image(u, maxPixel: 300) } }
            var r: [CGImage?] = []; for await i in g { r.append(i) }; return r
        }
        XCTAssertEqual(results.compactMap { $0 }.count, 20)
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 1)
        let again = await l.image(u, maxPixel: 300)
        XCTAssertNotNil(again)
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 1, "a loaded picture comes from memory")
    }

    func testPictureIsCutDownToTheTileSize() async {
        let data = Self.png(800)
        StubProtocol.handler = { _ in (200, data) }
        let l = loader()
        let i = await l.image(URL(string: "http://logos.test/big.png")!, maxPixel: 200)
        XCTAssertEqual(max(i?.width ?? 0, i?.height ?? 0), 200)
    }

    func testFailureRetriesOnceThenIsRemembered() async {
        StubProtocol.handler = { _ in (404, Data()) }
        let l = loader()
        let u = URL(string: "http://logos.test/missing.png")!
        let a = await l.image(u, maxPixel: 300)
        XCTAssertNil(a)
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 2, "one try and one retry")
        let b = await l.image(u, maxPixel: 300)
        XCTAssertNil(b)
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 2, "the failure is remembered, no new request")
    }

    func testFailureIsForgottenAfterItsTime() async throws {
        StubProtocol.handler = { _ in (500, Data()) }
        let l = loader(failureTTL: 0.3)
        let u = URL(string: "http://logos.test/flaky.png")!
        _ = await l.image(u, maxPixel: 300)
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 2)
        try await Task.sleep(for: .milliseconds(400))
        let data = Self.png()
        StubProtocol.handler = { _ in (200, data) }
        let i = await l.image(u, maxPixel: 300)
        XCTAssertNotNil(i, "after the time the loader asks again")
        XCTAssertEqual(StubProtocol.count(u.absoluteString), 3)
    }

    func testRetryCanSucceed() async {
        let data = Self.png()
        let n = NSLock(); nonisolated(unsafe) var calls = 0
        StubProtocol.handler = { _ in n.lock(); calls += 1; let c = calls; n.unlock(); return c == 1 ? (503, Data()) : (200, data) }
        let l = loader()
        let i = await l.image(URL(string: "http://logos.test/second.png")!, maxPixel: 300)
        XCTAssertNotNil(i)
    }

    func testHostThatDoesNotAnswerFailsTheRestAtOnce() async {
        StubProtocol.handler = nil
        StubProtocol.failure = NSURLErrorTimedOut
        let l = loader()
        let first = URL(string: "http://dead.test/1.png")!
        _ = await l.image(first, maxPixel: 300)
        XCTAssertEqual(StubProtocol.count(first.absoluteString), 1, "a timeout is not retried")
        for n in 2...6 { _ = await l.image(URL(string: "http://dead.test/\(n).png")!, maxPixel: 300) }
        let total = StubProtocol.hits.values.reduce(0, +)
        XCTAssertEqual(total, 1, "the other pictures of that host never leave the app")
        let count = await l.requestCount
        XCTAssertEqual(count, 1)
    }
}
