import XCTest
@testable import NexusTVMac

/// The three source adapters on recorded fixtures (Fixtures/): no provider, no login, no network.
final class SourceTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        let b = Bundle(for: SourceTests.self)
        let parts = name.split(separator: ".").map(String.init)
        if let u = b.url(forResource: parts[0], withExtension: parts.dropFirst().joined(separator: ".")) { return u }
        XCTFail("fixture \(name) missing"); return URL(fileURLWithPath: "/nonexistent")
    }
    private func fixture(_ name: String) -> String { (try? String(contentsOf: fixtureURL(name), encoding: .utf8)) ?? "" }

    private func parsed(_ name: String, chunk: Int? = nil) -> M3UParser {
        StreamHeaderRegistry.shared.clear()
        let p = M3UParser()
        let data = Data(fixture(name).utf8)
        if let chunk {
            var i = 0
            while i < data.count { p.feed(data.subdata(in: i..<min(i + chunk, data.count)), last: false); i += chunk }
            p.feed(Data(), last: true)
        } else { p.feed(data, last: true) }
        return p
    }
    private func names(_ p: M3UParser, _ g: String) -> [String] { p.store.live.by[g]?.map(\.name) ?? [] }

    // MARK: M3U gap rules

    func testBOMAndCRLFAreStripped() {
        let p = parsed("gaps.m3u")
        XCTAssertEqual(p.store.guide, "https://guide.example.invalid/epg.xml.gz", "first of a comma list; url-tvg wins over x-tvg-url")
        XCTAssertEqual(names(p, "News").first, "One")
        XCTAssertFalse(p.store.live.order.contains { $0.contains("\r") || $0.hasPrefix("\u{FEFF}") })
    }

    func testGroupTitleWithSemicolonsPutsTheChannelInEachGroup() {
        let p = parsed("gaps.m3u")
        for g in ["Sport", "Kids", "Family"] { XCTAssertEqual(names(p, g), ["Multi Channel"], g) }
    }

    func testExtgrpNamesTheGroup() {
        XCTAssertEqual(names(parsed("gaps.m3u"), "Music"), ["Grouped By Extgrp"])
    }

    func testPerChannelHeaders() {
        _ = parsed("gaps.m3u")
        let r = StreamHeaderRegistry.shared
        XCTAssertEqual(r.headers(for: "http://stream.example.invalid/live/agent.m3u8"), StreamHeaders(userAgent: "AgentFromVlcOpt/1.0", referrer: "https://ref.example.invalid/"))
        XCTAssertEqual(r.headers(for: "http://stream.example.invalid/live/attr.m3u8"), StreamHeaders(userAgent: "AgentFromAttr/2.0", referrer: "https://attr.example.invalid/"))
        XCTAssertEqual(r.headers(for: "http://stream.example.invalid/live/kodi.m3u8"), StreamHeaders(userAgent: "KodiAgent/3.0", referrer: "https://kodi.example.invalid/"), "Kodi pipe headers; the pipe is cut from the address")
        XCTAssertNil(r.headers(for: "http://stream.example.invalid/live/one.m3u8"))
        XCTAssertTrue(parsed("gaps.m3u").store.live.by["News"]?.contains { $0.id == "http://stream.example.invalid/live/kodi.m3u8" } ?? false)
    }

    func testFilmsAndSeriesOnlyWhenTheListMarksThem() {
        let p = parsed("gaps.m3u")
        XCTAssertEqual(p.store.vod.by["Cinema"]?.map(\.name), ["A Film By Extension"])
        XCTAssertEqual(p.store.vod.by["Cinema"]?.first?.ext, "mkv")
        XCTAssertEqual(p.store.vod.by["Movies"]?.map(\.name), ["A Film By Group"], "a film group holds films")
        XCTAssertEqual(names(p, "Movies"), ["Live Movie Channel"], "a live stream in a movie group stays live")
        let shows = p.store.series.by["Series"] ?? []
        XCTAssertEqual(shows.map(\.name), ["Some Show"])
        let eps = p.store.episodes(of: shows[0].id)
        XCTAssertEqual(eps["1"]?.map(\.num), [1, 2])
        XCTAssertEqual(eps["2"]?.map(\.num), [1])
        XCTAssertEqual(eps["1"]?.first?.title, "Pilot")
    }

    func testChunkBoundariesChangeNothing() {
        let whole = parsed("gaps.m3u"), chunked = parsed("gaps.m3u", chunk: 7)
        XCTAssertEqual(whole.store.live.order, chunked.store.live.order)
        XCTAssertEqual(whole.store.live.count, chunked.store.live.count)
        XCTAssertEqual(whole.store.guide, chunked.store.guide)
        XCTAssertEqual(whole.store.vod.count, chunked.store.vod.count)
    }

    func testIndexModeCountsAndFilterKeepsOnlyTickedGroups() {
        let p = M3UParser(); p.mode = .index
        p.feed(Data(fixture("groups.m3u").utf8), last: true)
        XCTAssertEqual(p.groupCounts.map(\.n), [40, 30, 20])
        XCTAssertEqual(p.store.entryCount, 0, "index mode keeps no entry")
        XCTAssertTrue(p.needsSecondRead(for: ["Beta"]))
        let q = M3UParser(); q.mode = .filter; q.keep = ["Beta"]; q.capKept = 25
        q.feed(Data(fixture("groups.m3u").utf8), last: true)
        XCTAssertEqual(q.store.live.by["Beta"]?.count, 25, "the keep limit stops the group")
        XCTAssertNil(q.store.live.by["Alpha"])
        XCTAssertTrue(q.capped)
    }

    func testSetKeepDropsUntickedGroupsAlreadyHeld() {
        let p = M3UParser()
        p.feed(Data(fixture("groups.m3u").utf8), last: true)
        XCTAssertEqual(p.store.live.count, 90)
        p.setKeep(["Gamma"])
        XCTAssertEqual(p.store.live.order, ["Gamma"])
        XCTAssertEqual(p.kept, 20)
        XCTAssertFalse(p.needsSecondRead(for: ["Gamma"]))
    }

    // MARK: Xtream export link

    func testXtreamExportLinkInAnyOrder() {
        let l = XtreamLink.parse(fixture("xtream-export-link.txt"))
        XCTAssertEqual(l, XtreamLink(base: "http://panel.example.invalid:8080", user: "demo_user", pass: "demo_pass"))
        XCTAssertEqual(XtreamLink.parse("panel.example.invalid/get.php?password=p%40ss&output=ts&username=u"), XtreamLink(base: "http://panel.example.invalid", user: "u", pass: "p@ss"))
        XCTAssertNil(XtreamLink.parse("http://panel.example.invalid/get.php?username=only"))
        XCTAssertNil(XtreamLink.parse("https://lists.example.invalid/playlist.m3u"))
    }

    func testXtreamAdapterBuildsStreamURLs() {
        let x = XtreamSource(account: Account(server: "http://panel.example.invalid:8080/", username: "demo_user", password: "demo_pass"))
        XCTAssertEqual(x.streamURL(kind: .live, id: "12", ext: "")?.absoluteString, "http://panel.example.invalid:8080/live/demo_user/demo_pass/12.m3u8")
        XCTAssertEqual(x.streamURL(kind: .film, id: "5", ext: "mkv")?.absoluteString, "http://panel.example.invalid:8080/movie/demo_user/demo_pass/5.mkv")
        XCTAssertEqual(x.streamURL(kind: .episode, id: "9", ext: "")?.absoluteString, "http://panel.example.invalid:8080/series/demo_user/demo_pass/9.mkv")
        XCTAssertNil(x.streamURL(kind: .series, id: "1", ext: ""))
    }

    // MARK: M3U source over a file (the streaming path)

    func testSourceStreamsAFileAndReportsItsGuide() async throws {
        let s = M3USource(url: fixtureURL("gaps.m3u"))
        s.start(); defer { s.cancel() }
        try await s.waitForFirst()
        let cats = try await s.liveCategories()
        XCTAssertTrue(cats.map(\.name).contains("News"))
        let v1 = try await s.liveStreams(category: "Sport").map(\.name)
        XCTAssertEqual(v1, ["Multi Channel"])
        XCTAssertEqual(s.guideURL, "https://guide.example.invalid/epg.xml.gz")
        XCTAssertEqual(s.streamURL(kind: .live, id: "http://stream.example.invalid/live/one.m3u8", ext: "")?.host, "stream.example.invalid")
        let info = try await s.info(film: false, id: "s:some show")
        XCTAssertEqual((info["episodes"] as? [String: Any])?.keys.sorted(), ["1", "2"])
    }

    func testSourceRefusesWhatIsNotAPlaylist() async {
        for name in ["notplaylist.html", "empty.m3u"] {
            let s = M3USource(url: fixtureURL(name))
            s.start(); defer { s.cancel() }
            do { try await s.waitForFirst(); XCTFail("\(name) must not load") }
            catch { XCTAssertEqual(error as? SourceError, .notAPlaylist, name) }
        }
    }

    func testBigPlaylistAsksForGroupsThenKeepsOnlyThose() async throws {
        let picking = expectation(description: "picker asked")
        picking.assertForOverFulfill = false
        let s = M3USource(url: fixtureURL("groups.m3u"), limitBytes: 400, capKept: 60_000)
        s.onPicker = { st in if st.done { picking.fulfill() } }
        s.start(); defer { s.cancel() }
        await fulfillment(of: [picking], timeout: 10)
        XCTAssertTrue(s.isPicking)
        let st = s.pickerState()
        XCTAssertEqual(st.groups.map(\.name), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(st.groups.map(\.n), [40, 30, 20])
        s.keepGroups(["Gamma"])
        for _ in 0..<100 where s.isStreaming { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(s.chosenGroups, ["Gamma"])
        let v2 = try await s.liveStreams(category: nil).count
        XCTAssertEqual(v2, 20)
        let v3 = try await s.liveCategories().map(\.name)
        XCTAssertEqual(v3, ["Gamma"])
    }

    // MARK: Portal

    private func portalReplies() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL("portal-replies.json"))) as! [String: Any]
    }
    private func stubbed(mac: String = "00:1A:79:00:00:01", refuse: Bool = false) throws -> (PortalSource, Box) {
        let r = try portalReplies(), box = Box()
        let p = PortalSource(base: "http://portal.example.invalid/c/", mac: mac)
        p.transport = { req in
            let q = req.url?.query ?? ""
            box.calls.append(q.components(separatedBy: "&").first { $0.hasPrefix("action=") } ?? q)
            box.requests.append(req)
            func reply(_ k: String) -> Data { try! JSONSerialization.data(withJSONObject: r[k]!) }
            if q.contains("action=handshake") { return refuse ? Data("{\"js\":[]}".utf8) : reply("handshake") }
            if q.contains("action=get_profile") { return reply("get_profile") }
            if q.contains("action=get_genres") { return reply("get_genres") }
            if q.contains("action=get_all_channels") { return reply("get_all_channels") }
            if q.contains("type=vod&action=get_categories") { return reply("vod_categories") }
            if q.contains("type=series&action=get_categories") { return reply("series_categories") }
            if q.contains("type=vod&action=get_ordered_list") { return reply("vod_list") }
            if q.contains("action=create_link") { return reply("create_link") }
            return Data("{\"js\":[]}".utf8)
        }
        return (p, box)
    }
    final class Box: @unchecked Sendable { var calls: [String] = []; var requests: [URLRequest] = [] }

    func testPortalMACFormat() {
        XCTAssertTrue(PortalSource.validMAC("00:1A:79:AB:CD:EF"))
        XCTAssertTrue(PortalSource.validMAC(" 00:1a:79:ab:cd:ef "))
        XCTAssertFalse(PortalSource.validMAC("00:1A:79:AB:CD"))
        XCTAssertFalse(PortalSource.validMAC("not a mac"))
    }

    func testPortalCallOrderAndLibrary() async throws {
        let (p, box) = try stubbed()
        XCTAssertEqual(p.endpoint, "http://portal.example.invalid/portal.php")
        let genres = try await p.liveCategories()
        XCTAssertEqual(genres.map(\.name), ["News", "Sport"], "the * (All) entry is dropped")
        XCTAssertEqual(Array(box.calls.prefix(3)), ["action=handshake", "action=get_profile", "action=get_genres"])
        let cookie = box.requests.first?.value(forHTTPHeaderField: "Cookie") ?? ""
        XCTAssertTrue(cookie.hasPrefix("mac=00:1A:79:00:00:01"))
        XCTAssertEqual(box.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN123")
        let sport = try await p.liveStreams(category: "2")
        XCTAssertEqual(sport.map(\.name), ["Portal Two"])
        XCTAssertEqual(sport.first?.icon, "https://img.example.invalid/11.png")
        let news = try await p.liveStreams(category: "1")
        XCTAssertEqual(news.first?.icon, "http://portal.example.invalid/stalker_portal/misc/logos/320/10.png")
        let v4 = try await p.vodCategories().map(\.name)
        XCTAssertEqual(v4, ["Drama"])
        let v5 = try await p.vodStreams(category: "5").map(\.name)
        XCTAssertEqual(v5, ["Portal Film", "Portal Film Two"])
        let v6 = try await p.seriesCategories().map(\.name)
        XCTAssertEqual(v6, ["Shows"])
    }

    func testPortalStreamURLIsMadeOnDemand() async throws {
        let (p, _) = try stubbed()
        let ph = p.streamURL(kind: .live, id: "ffrt http://localhost/ch/10", ext: "")
        XCTAssertEqual(ph?.scheme, "nxportal")
        XCTAssertEqual(PortalSource.decode(ph!)?.cmd, "ffrt http://localhost/ch/10")
        let real = await p.resolve(ph!)
        XCTAssertEqual(real?.absoluteString, "http://media.example.invalid/play/abc.m3u8", "the leading player word is cut")
    }

    func testPortalRefusingTheMACIsRefused() async throws {
        let (p, _) = try stubbed(refuse: true)
        do { try await p.ensure(); XCTFail("must refuse") } catch { XCTAssertEqual(error as? SourceError, .refused) }
    }

    func testPortalEndpointForStalkerPath() {
        XCTAssertEqual(PortalSource(base: "http://p.example.invalid/stalker_portal/c", mac: "00:1A:79:00:00:01").endpoint, "http://p.example.invalid/stalker_portal/server/load.php")
    }

    // MARK: saved records and messages

    func testAccountsSavedByEarlierBuildsAreXtream() throws {
        let old = #"{"id":"default","name":"My IPTV","server":"http://h.example.invalid","username":"u","password":"p"}"#
        let a = try JSONDecoder().decode(StoredAccount.self, from: Data(old.utf8))
        XCTAssertEqual(a.type, .xtream)
        XCTAssertNil(a.groups)
        XCTAssertTrue(a.makeSource() is XtreamSource)
        let m = StoredAccount(id: "m", name: "List", server: "https://l.example.invalid/a.m3u", username: "", password: "", type: .m3u, epg: "https://g.example.invalid/x.xml", groups: ["News"])
        let back = try JSONDecoder().decode(StoredAccount.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        XCTAssertTrue(back.makeSource() is M3USource)
    }

    func testWhichRowsTurnRed() {
        XCTAssertEqual(SourceChecker.failure(.xtream, .server).marks, [.bad, .none, .none], "server unreachable = first row")
        XCTAssertEqual(SourceChecker.failure(.xtream, .auth).marks, [.ok, .bad, .bad], "auth refused = rows 2 and 3")
        XCTAssertEqual(SourceChecker.failure(.m3u, .invalid).message, "This link is not a playlist.")
        XCTAssertEqual(SourceChecker.failure(.portal, .auth).marks, [.ok, .bad, .none], "portal refusing the MAC = MAC row")
    }
}
