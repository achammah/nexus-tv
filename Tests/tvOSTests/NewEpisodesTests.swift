import XCTest
@testable import NexusTV

private func ep(_ s: Int, _ n: Int, title: String = "") -> EpisodeRef { EpisodeRef(id: "s\(s)e\(n)", season: s, num: n, title: title, ext: "mkv") }
private func series(_ id: String, img: String = "") -> MediaItem { MediaItem(kind: .series, id: id, name: "Show " + id, img: img) }
private func snap(_ eps: [EpisodeRef]) -> FollowedShows.Snapshot { .init(episodes: eps, poster: "p.jpg", backdrop: "b.jpg", plot: "plot", facts: ["2024"]) }

/// "New episodes": the seen set, the new-episode diff, the followed shows, the refresh rules and the hero order. No provider call.
@MainActor
final class NewEpisodesTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "nx.test." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func store(_ d: UserDefaults, account: String = "default") -> FollowedShows { FollowedShows(defaults: d, accountId: { account }) }

    // MARK: the diff

    func testNewEpisodesAreTheOnesNotInTheSeenSet() {
        let current = [ep(1, 1), ep(1, 2), ep(1, 3), ep(2, 1)]
        let fresh = EpisodeDiff.newEpisodes(current: current, seen: ["s1e1", "s1e2"])
        XCTAssertEqual(fresh.map(\.id), ["s2e1", "s1e3"], "newest first: the later season, then the later episode")
        XCTAssertEqual(fresh.first?.label, "S2 E1")
        XCTAssertEqual(EpisodeDiff.newEpisodes(current: current, seen: Set(current.map(\.id))), [])
        XCTAssertEqual(EpisodeDiff.newEpisodes(current: current, seen: nil), [], "a show never recorded has nothing new")
    }

    func testAProviderReindexIsNotNewEpisodes() {
        XCTAssertTrue(EpisodeDiff.reindexed(current: [ep(1, 1), ep(1, 2)], seen: ["x1", "x2"]), "none of the seen ids is left")
        XCTAssertFalse(EpisodeDiff.reindexed(current: [ep(1, 1), ep(1, 2)], seen: ["s1e1"]))
        XCTAssertFalse(EpisodeDiff.reindexed(current: [ep(1, 1)], seen: []))
    }

    func testMergedKeepsOrderAndAddsOnce() {
        XCTAssertEqual(EpisodeDiff.merged(["a", "b"], with: [ep(1, 1), EpisodeRef(id: "b", season: 1, num: 2, title: ""), EpisodeRef(id: "c", season: 1, num: 3, title: "")]),
                       ["a", "b", "s1e1", "c"])
    }

    func testFollowedShowsAreMyListPlusContinueWatchingMostRecentFirst() {
        func rp(_ sid: String, at: TimeInterval) -> ResumePoint {
            let e = MediaItem(kind: .episode, id: "e" + sid, name: "x", seriesId: sid, seriesName: "Show " + sid)
            return ResumePoint(item: e, posMs: 1, durMs: 2, at: Date(timeIntervalSince1970: at))
        }
        let film = MediaItem(kind: .film, id: "f", name: "Film")
        let f = EpisodeDiff.followed(myList: [series("A", img: "a.jpg"), film, series("B")], resume: [rp("B", at: 1), rp("C", at: 2), rp("A", at: 0)])
        XCTAssertEqual(f.map(\.id), ["C", "B", "A"], "Continue watching by time, then My List; films are not followed")
        XCTAssertEqual(f.last?.img, "a.jpg", "a show in My List keeps its poster")
        let many = (0..<40).map { series("m\($0)") }
        XCTAssertEqual(EpisodeDiff.followed(myList: many, resume: []).count, 30, "at most 30")
    }

    func testPlanPlaysTheEpisodeAndQueuesTheOnesAfter() {
        let eps = [ep(1, 1), ep(1, 2), ep(2, 1, title: "Back")]
        let p = EpisodeDiff.plan(episodes: eps.reversed(), play: "s1e2", series: series("A"), title: "Show A", poster: "p.jpg")
        XCTAssertEqual(p?.item.name, "Show A · S1 E2")
        XCTAssertEqual(p?.item.seriesId, "A")
        XCTAssertEqual(p?.next.map(\.id), ["s2e1"])
        XCTAssertNil(EpisodeDiff.plan(episodes: eps, play: "nope", series: series("A"), title: "t", poster: ""))
    }

    // MARK: the seen set

    func testTheSeenSetIsKeptPerAccount() {
        let d = suite()
        let a = store(d, account: "one")
        a.record("A", episodes: [ep(1, 1), ep(1, 2)])
        XCTAssertEqual(store(d, account: "one").seenIds("A"), ["s1e1", "s1e2"], "a new run of the app reads it back")
        XCTAssertNil(store(d, account: "two").seenIds("A"), "another account has its own sets")
        a.record("A", episodes: [ep(1, 3)])
        XCTAssertEqual(a.seenIds("A"), ["s1e1", "s1e2", "s1e3"], "recording adds to the set")
    }

    func testOpeningTheShowPageReturnsTheNewEpisodesAndRecordsEverything() {
        let f = store(suite())
        f.record("A", episodes: [ep(1, 1)])
        let fresh = f.opened(series("A"), snapshot: snap([ep(1, 1), ep(1, 2), ep(1, 3)]))
        XCTAssertEqual(fresh, ["s1e2", "s1e3"], "these carry the NEW pill during the visit")
        XCTAssertEqual(f.seenIds("A"), ["s1e1", "s1e2", "s1e3"], "the badge clears: all of it is seen")
        XCTAssertEqual(f.opened(series("A"), snapshot: snap([ep(1, 1), ep(1, 2), ep(1, 3)])), [], "a second visit has no pills")
        XCTAssertEqual(f.opened(series("Z"), snapshot: snap([ep(1, 1)])), [], "a show seen for the first time has nothing new")
        XCTAssertTrue(f.hasRecord("Z"))
    }

    // MARK: the refresh

    func testRefreshRecordsABaselineThenFindsTheNewEpisode() async {
        let d = suite(), f = store(d)
        var listing = [ep(1, 1), ep(1, 2)]
        f.fetch = { _ in snap(listing) }
        let a = series("A")
        await f.refresh(followed: [a], force: true)
        XCTAssertTrue(f.shows.isEmpty, "first sight is a baseline, never a flood of new episodes")
        XCTAssertEqual(f.seenIds("A"), ["s1e1", "s1e2"])

        listing += [ep(2, 1, title: "Return"), ep(2, 2, title: "Again")]
        await f.refresh(followed: [a], force: true)
        XCTAssertEqual(f.shows.count, 1)
        let n = f.shows[0]
        XCTAssertEqual(n.badge, "2 new")
        XCTAssertEqual(n.caption, "S2 E2 · Again")
        XCTAssertEqual(n.kicker, "NEW EPISODE · S2 E2")
        XCTAssertEqual(n.series.img, "p.jpg", "the poster comes from the series info")
        XCTAssertEqual(n.backdrop, "b.jpg")

        // the result is stored: the next run of the app draws the row at once
        XCTAssertEqual(store(d).visible(followed: [a]).map(\.id), ["A"])
        XCTAssertEqual(store(d).visible(followed: []).count, 0, "a show that left My List leaves the row")
    }

    func testRefreshRunsOnceAnHourAndAgainWhenForced() async {
        let f = store(suite())
        var calls = 0, clock = Date(timeIntervalSince1970: 1_000_000)
        f.now = { clock }
        f.fetch = { _ in calls += 1; return snap([ep(1, 1)]) }
        await f.refresh(followed: [series("A")])
        XCTAssertEqual(calls, 1)
        clock += 3599
        await f.refresh(followed: [series("A")])
        XCTAssertEqual(calls, 1, "under an hour: the stored result stands")
        clock += 2
        await f.refresh(followed: [series("A")])
        XCTAssertEqual(calls, 2, "an hour later it asks again")
        await f.refresh(followed: [series("A")], force: true)
        XCTAssertEqual(calls, 3)
    }

    func testRefreshReadsAtMost30ShowsThreeAtATime() async {
        let f = store(suite())
        var calls = 0, inFlight = 0, peak = 0
        f.fetch = { _ in
            calls += 1; inFlight += 1; peak = max(peak, inFlight)
            try? await Task.sleep(nanoseconds: 5_000_000)
            inFlight -= 1
            return snap([ep(1, 1)])
        }
        await f.refresh(followed: (0..<45).map { series("m\($0)") }, force: true)
        XCTAssertEqual(calls, 30)
        XCTAssertLessThanOrEqual(peak, 3)
        XCTAssertGreaterThan(peak, 1, "they do run side by side")
    }

    func testAFailedReadKeepsTheKnownRowAndAnOfflineRefreshIsNotCounted() async {
        let f = store(suite())
        f.fetch = { _ in snap([ep(1, 1)]) }
        let a = series("A")
        await f.refresh(followed: [a], force: true)
        f.fetch = { _ in snap([ep(1, 1), ep(1, 2)]) }
        await f.refresh(followed: [a], force: true)
        XCTAssertEqual(f.shows.count, 1)
        f.fetch = { _ in nil }
        let before = f.checkedAt
        await f.refresh(followed: [a], force: true)
        XCTAssertEqual(f.shows.count, 1, "a failed read keeps what was known")
        XCTAssertEqual(f.checkedAt, before, "nothing was read: the hour does not start")
    }

    func testPlayingAnEpisodeClearsTheShowFromTheRow() async {
        let f = store(suite())
        f.fetch = { _ in snap([ep(1, 1)]) }
        let a = series("A")
        await f.refresh(followed: [a], force: true)
        f.fetch = { _ in snap([ep(1, 1), ep(1, 2)]) }
        await f.refresh(followed: [a], force: true)
        XCTAssertEqual(f.shows.count, 1)
        f.played(a)
        XCTAssertTrue(f.shows.isEmpty)
        XCTAssertEqual(f.seenIds("A"), ["s1e1", "s1e2"])
        await f.refresh(followed: [a], force: true)
        XCTAssertTrue(f.shows.isEmpty, "the next refresh does not bring it back")
    }

    func testAddingAShowToMyListRecordsItsEpisodes() async {
        let f = store(suite())
        f.fetch = { _ in snap([ep(1, 1), ep(1, 2)]) }
        f.noteFollowed(series("A"))
        for _ in 0..<50 where !f.hasRecord("A") { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(f.seenIds("A"), ["s1e1", "s1e2"])
    }

    func testSeasonHintIsTakenOnce() {
        let f = store(suite())
        f.seasonHint["A"] = "2"
        XCTAssertEqual(f.takeSeasonHint("A"), "2")
        XCTAssertNil(f.takeSeasonHint("A"))
    }

    // MARK: Home

    func testHeroPutsShowsWithNewEpisodesFirst() {
        let n = NewShow(series: series("A", img: "a.jpg"), episodes: [ep(2, 5), ep(2, 4)], backdrop: "b.jpg", plot: "p", facts: ["2024", "Drama"])
        let top = [HeroItem(id: "A", title: "Show A", year: "2020", genre: "X", rating: "8.1", plot: "p", backdrop: "b", cover: "c"),
                   HeroItem(id: "T", title: "Top", year: "2021", genre: "Y", rating: "7.5", plot: "p", backdrop: "b", cover: "c")]
        let h = HomeHero.list(updates: [n], base: top)
        XCTAssertEqual(h.map(\.id), ["A", "T"], "the top series that is also new appears once, first")
        XCTAssertEqual(h[0].kicker, "NEW EPISODE · S2 E5")
        XCTAssertEqual(h[1].kicker, "Top series")
        XCTAssertEqual(h[1].facts, ["2021", "Y", "★ 7.5"])
        XCTAssertEqual(HomeHero.list(updates: [], base: top).count, 2)
    }

    func testTheNewEpisodesRowIsFirstByDefaultAndSurvivesOldSettings() {
        XCTAssertEqual(Settings.defaultRows(["BE"]).first?.id, "updates")
        XCTAssertEqual(HomeRow.label("updates"), "New episodes")
        XCTAssertTrue(HomeRow.mac.contains("updates"))
        XCTAssertEqual(HomeRow.fixed.first, "updates")
    }
}
