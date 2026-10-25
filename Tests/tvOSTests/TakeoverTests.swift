import XCTest
@testable import NexusTV

/// Last device wins: the topic, the claim, the loss rule and the idle silence. A fake transport (it numbers the messages like
/// the server does) and a fake clock; no network.
final class FakeTakeover: TakeoverTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var feed: [(id: String, body: Data)] = [], _polls = 0, _sinces: [String] = []
    var failPublish = false
    var published: [Data] { lock.lock(); defer { lock.unlock() }; return feed.map(\.body) }
    var polls: Int { lock.lock(); defer { lock.unlock() }; return _polls }
    var sinces: [String] { lock.lock(); defer { lock.unlock() }; return _sinces }
    /// A message from another device, numbered after everything so far.
    func inject(_ m: TakeoverMessage) { lock.lock(); feed.append(("id\(feed.count + 1)", try! JSONEncoder().encode(m))); lock.unlock() }
    func publish(topic: String, body: Data) async throws -> String {
        lock.lock(); defer { lock.unlock() }
        if failPublish { throw URLError(.notConnectedToInternet) }
        let id = "id\(feed.count + 1)"; feed.append((id, body)); return id
    }
    func poll(topic: String, since: String) async throws -> Data {
        lock.lock(); defer { lock.unlock() }
        _polls += 1; _sinces.append(since)
        let from = feed.firstIndex { $0.id == since }.map { $0 + 1 } ?? 0
        return feed[from...].map { e -> Data in
            let o: [String: Any] = ["id": e.id, "time": 1, "event": "message", "topic": "x", "message": String(data: e.body, encoding: .utf8)!]
            return try! JSONSerialization.data(withJSONObject: o)
        }.reduce(into: Data()) { $0.append($1); $0.append(10) }
    }
}

@MainActor
final class TakeoverTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000)
    private func channel(_ t: FakeTakeover, dev: String = "me") -> TakeoverChannel {
        let c = TakeoverChannel(transport: t, device: dev, name: "Mac", now: { self.clock })
        c.topic = "nxtv-test"
        return c
    }
    private func msg(_ dev: String, _ kind: String = "play", t: Int = 1, name: String = "Frame TV") -> TakeoverMessage { .init(dev: dev, name: name, kind: kind, t: t) }
    /// The claim is published in the background: wait for the server's id.
    private func claimed(_ c: TakeoverChannel) async {
        c.claim()
        for _ in 0..<100 where c.claimId == nil { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testTopicIsStableHexAndPrivate() {
        let a = TakeoverChannel.topic(server: "http://s.example", username: "u", password: "p")
        XCTAssertEqual(a, TakeoverChannel.topic(server: "http://s.example", username: "u", password: "p"))
        XCTAssertNotEqual(a, TakeoverChannel.topic(server: "http://s.example", username: "u", password: "q"))
        XCTAssertTrue(a.hasPrefix("nxtv-"))
        let hex = a.dropFirst(5)
        XCTAssertEqual(hex.count, 24)
        XCTAssertTrue(hex.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertFalse(a.contains("u") && a.contains("http"))
    }

    func testClaimPublishesOneJSONMessageWithNothingSecretAndKeepsTheServerId() async throws {
        let t = FakeTakeover(), c = channel(t)
        await claimed(c)
        XCTAssertEqual(t.published.count, 1)
        let m = try JSONDecoder().decode(TakeoverMessage.self, from: t.published[0])
        XCTAssertEqual(m, TakeoverMessage(v: 1, dev: "me", name: "Mac", kind: "play", t: 1_000_000))
        XCTAssertEqual(c.claimId, "id1", "the id the server gave the claim")
        c.pause()
    }

    func testAForeignPlayAfterMyClaimMeansLostAndThePollStartsAtMyId() async {
        let t = FakeTakeover(), c = channel(t)
        var by: String?
        c.onLost = { by = $0 }
        await claimed(c)
        t.inject(msg("other", t: 1))          // its clock says 1 ms: the server order wins, not the clock
        await c.pollOnce()
        XCTAssertEqual(t.sinces, ["id1"])
        XCTAssertEqual(by, "Frame TV")
        XCTAssertFalse(c.holding)
        XCTAssertNil(c.claimId)
    }

    func testAForeignPlayBeforeMyClaimNeverAppearsInThePoll() async {
        let t = FakeTakeover()
        t.inject(msg("other", t: 9_999_999_999))      // older on the server, newer on its own clock
        let c = channel(t)
        var lost = false
        c.onLost = { _ in lost = true }
        await claimed(c)
        await c.pollOnce()
        XCTAssertFalse(lost)
        XCTAssertTrue(c.holding)
        c.pause()
    }

    func testOurOwnEchoAndStopsAreIgnored() async {
        let t = FakeTakeover(), c = channel(t)
        var lost = false
        c.onLost = { _ in lost = true }
        await claimed(c)
        t.inject(msg("me"))
        t.inject(msg("other", "stop"))
        await c.pollOnce()
        XCTAssertFalse(lost)
        XCTAssertTrue(c.holding)
        c.pause()
    }

    func testNoIdYetMeansNoPoll() async {
        let t = FakeTakeover()
        t.failPublish = true
        let c = channel(t)
        c.claim()
        await c.pollOnce()
        XCTAssertEqual(t.polls, 0, "the publish failed: playback goes on, nothing can be ordered, nothing is polled")
        c.pause()
    }

    func testNoPollAndNoPublishWhenNothingPlays() async throws {
        let t = FakeTakeover(), c = channel(t)
        await c.pollOnce()
        XCTAssertEqual(t.polls, 0, "never claimed")
        await claimed(c)
        c.pause()
        await c.pollOnce()
        XCTAssertEqual(t.polls, 0, "stream closed: no poll")
        c.resumeHolding()
        await c.pollOnce()
        XCTAssertEqual(t.polls, 1)
        c.leave()
        await c.pollOnce()
        XCTAssertEqual(t.polls, 1, "left: no poll")
        let idle = channel(FakeTakeover())
        idle.topic = nil
        idle.claim()
        XCTAssertFalse(idle.holding, "no account, no takeover")
    }

    func testAutomaticReopenKeepsItsClaim() async throws {
        let t = FakeTakeover(), c = channel(t)
        await claimed(c); c.pause()
        clock += 60
        c.resumeHolding()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(t.published.count, 1, "no second claim after a stall")
        XCTAssertEqual(c.claimId, "id1")
        c.pause()
    }

    func testEventsReadTheNtfyLines() {
        let line = #"{"id":"a1","time":5,"event":"message","topic":"x","message":"{\"v\":1,\"dev\":\"d\",\"name\":\"Apple TV\",\"kind\":\"play\",\"t\":7}"}"#
        let open = #"{"id":"a2","time":6,"event":"open","topic":"x"}"#
        let junk = #"{"id":"a3","time":7,"event":"message","topic":"x","message":"hello"}"#
        let ev = TakeoverChannel.events(Data([line, open, junk].joined(separator: "\n").utf8))
        XCTAssertEqual(ev.map(\.id), ["a1", "a3"])
        XCTAssertEqual(ev[0].message?.name, "Apple TV")
        XCTAssertNil(ev[1].message)
    }
}
