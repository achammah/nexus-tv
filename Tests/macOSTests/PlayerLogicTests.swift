import XCTest
@testable import NexusTVMac

/// The player rules that need no screen: track labels (rule 2), the credits cue (rule 5), the end-card ring and the
/// "Still watching?" counters (rules 4 and 6). No stream is opened.
final class PlayerLogicTests: XCTestCase {
    // MARK: track labels

    func testTwoEnglishAudioTracksAreToldApartByTheirTitleNotByANumber() {
        let l = TrackLabel.make(tracks: [
            TrackInput(id: 1, raw: "Track 1 - [English]", channels: 6, codec: "AC3"),
            TrackInput(id: 2, raw: "Track 2 - [English]", title: "Audio Description", channels: 2, codec: "AAC"),
            TrackInput(id: 3, raw: "Track 3 - [German]", channels: 6, codec: "AC3"),
        ])
        XCTAssertEqual(l.map(\.text), ["English", "English · Descriptive", "German"])
        XCTAssertEqual(l.map(\.detail), ["5.1 · AC3", "stereo · AAC", "5.1 · AC3"])
        XCTAssertEqual(l[0].flag, "flag-gb")
        XCTAssertEqual(l[2].flag, "flag-de")
    }

    func testTwoGermanTracksWithNoKeywordShowChannelsAndCodecAtTheRight() {
        let l = TrackLabel.make(tracks: [
            TrackInput(id: 1, raw: "Track 1 - [German]", channels: 6, codec: "AC3"),
            TrackInput(id: 2, raw: "Track 2 - [German]", channels: 2, codec: "AAC"),
        ])
        XCTAssertEqual(l.map(\.text), ["German", "German"])
        XCTAssertEqual(l.map(\.detail), ["5.1 · AC3", "stereo · AAC"])
        XCTAssertFalse(l.contains { $0.text.contains("German 1") || $0.text.contains("German 2") })
    }

    func testTwoTracksThatReadTheSameGetTheirPositionNeverEnglish1() {
        let l = TrackLabel.make(tracks: [
            TrackInput(id: 4, raw: "Track 1 - [English]", channels: 2, codec: "AAC"),
            TrackInput(id: 5, raw: "Track 2 - [English]", channels: 2, codec: "AAC"),
        ])
        XCTAssertEqual(l.map(\.text), ["English · Track 1", "English · Track 2"])
        XCTAssertFalse(l.contains { $0.text.hasSuffix("English 1") || $0.text.hasSuffix("English 2") })
    }

    func testNoLanguageAtAllIsTrackNUnknownLanguageWithAGreyCircle() {
        let l = TrackLabel.make(tracks: [
            TrackInput(id: 1, raw: "Track 1 - [English]", channels: 2),
            TrackInput(id: 6, raw: "Track 2", channels: 2, codec: nil),
        ])
        XCTAssertEqual(l[1].text, "Track 2")
        XCTAssertEqual(l[1].full, "Track 2 · unknown language")
        XCTAssertEqual(l[1].detail, "unknown language · stereo")
        XCTAssertNil(l[1].flag)
    }

    func testSubtitleKeywordsOnlyWhenTwoShareALanguage() {
        let l = TrackLabel.make(tracks: [
            TrackInput(id: 1, raw: "English"),
            TrackInput(id: 2, raw: "English", title: "English SDH"),
            TrackInput(id: 3, raw: "English", title: "Forced"),
            TrackInput(id: 4, raw: "French", title: "Forced"),
        ])
        XCTAssertEqual(l.map(\.text), ["English", "English · SDH", "English · Forced", "French"])
        XCTAssertEqual(l[1].detail, "hearing impaired")
        XCTAssertEqual(l[2].detail, "signs only")
        XCTAssertEqual(l[3].flag, "flag-fr")
    }

    func testDetectedLanguageWinsWhenTheFileHasNoTag() {
        let l = TrackLabel.make(tracks: [TrackInput(id: 9, raw: "Track 3", language: "Dutch")])
        XCTAssertEqual(l[0].text, "Dutch")
        XCTAssertEqual(l[0].flag, "flag-nl")
    }

    // MARK: credits cue

    private func memory() -> CreditsMemory {
        let name = "nx.test.credits." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return CreditsMemory(defaults: d, key: "nx_credits")
    }

    func testTheShowsMemoryIsTheMedianOfItsLastFiveSamples() {
        let m = memory()
        for v in [300.0, 120, 100, 90, 110, 130] { m.record("s1", secondsBeforeEnd: v) }     // 300 is the oldest: out of the last 5
        XCTAssertEqual(m.samples("s1"), [120, 100, 90, 110, 130])
        XCTAssertEqual(m.median("s1"), 110)
        XCTAssertEqual(creditsCue(for: "s1", duration: 3000, memory: m), 2890)
        XCTAssertNil(m.median("s2"), "another show has its own memory")
    }

    func testASampleOutsideTheLast8MinutesIsIgnored() {
        let m = memory()
        m.record("s1", secondsBeforeEnd: 600)
        m.record("s1", secondsBeforeEnd: 2)
        XCTAssertNil(m.median("s1"))
    }

    func testMemoryBeatsSubtitlesAndSubtitlesBeatTheTail() {
        let m = memory()
        // dense cues to 2820 s, a 50 s hole inside the last 6 minutes (2700 to 2750), dense again, then quiet to the end of 3000 s
        let cues = stride(from: 60.0, through: 2700, by: 10).map { $0 } + stride(from: 2750.0, through: 2820, by: 10).map { $0 }
        XCTAssertEqual(creditsCue(for: "s1", duration: 3000, memory: m, cueStarts: cues), 2823, "the last quiet stretch of 45 s or more: 3 s after the last cue")
        m.record("s1", secondsBeforeEnd: 150)
        XCTAssertEqual(creditsCue(for: "s1", duration: 3000, memory: m, cueStarts: cues), 2850, "the show's own memory comes first")
    }

    func testNoSubtitlesTakesTheLastTwoPercentNeverUnder20Seconds() {
        let m = memory()
        XCTAssertEqual(creditsCue(for: nil, duration: 3000, memory: m), 2940)
        XCTAssertEqual(creditsCue(for: nil, duration: 600, memory: m), 580, "2 % of 600 s is 12 s: the floor of 20 s applies")
        XCTAssertEqual(creditsCue(for: "unknown-show", duration: 3000, memory: m, cueStarts: []), 2940)
    }

    func testAQuietStretchRunningIntoTheLastSixMinutesStartsAtTheirBeginning() {
        let cues = stride(from: 60.0, through: 2600, by: 10).map { $0 }
        // 2600 → 3000 is quiet but the last 6 minutes start at 2640: the quiet stretch runs inside the window, so it counts from 2640
        XCTAssertEqual(Credits.quietPoint(cueStarts: cues, duration: 3000), 2640)
        XCTAssertNil(Credits.quietPoint(cueStarts: [], duration: 3000))
        XCTAssertNil(Credits.quietPoint(cueStarts: stride(from: 60.0, through: 2990, by: 10).map { $0 }, duration: 3000), "dialogue to the end: no quiet stretch")
    }

    // MARK: ring and still watching

    func testTheRingRunsOnlyWhenThePreviousEpisodeReachedItsCardWithoutASeek() {
        var a = AutoplayState()
        XCTAssertFalse(a.cardReached(), "first episode of the session: the card waits")
        _ = a.episodeStarted(autoplayed: true, windowKey: false)
        XCTAssertTrue(a.cardReached(), "the previous one reached its card without a seek")
        a.seeked()
        _ = a.episodeStarted(autoplayed: true, windowKey: false)
        XCTAssertFalse(a.cardReached(), "the previous one was seeked")
    }

    func testStillWatchingAsksAfterTwoAutoplayedEpisodesWithNoKey() {
        var a = AutoplayState()
        let t = Date()
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: false, at: t))
        XCTAssertTrue(a.episodeStarted(autoplayed: true, windowKey: false, at: t))
    }

    func testAKeyPressRestartsTheCountAndBlocksTheAskFor90Minutes() {
        var a = AutoplayState()
        let t = Date()
        _ = a.episodeStarted(autoplayed: true, windowKey: false, at: t)
        a.key(at: t)
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(60)), "the count restarted")
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(120)), "a key was pressed 2 minutes ago")
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(80 * 60)))
        XCTAssertTrue(a.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(95 * 60)), "more than 90 minutes since the key")
    }

    func testOnTheMacAnActiveWindowWithAMovingMouseIsNeverAsked() {
        var a = AutoplayState()
        let t = Date()
        a.mouse(at: t)
        _ = a.episodeStarted(autoplayed: true, windowKey: true, at: t.addingTimeInterval(10))
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: true, at: t.addingTimeInterval(20)), "window key and mouse moved in the last 90 minutes")
        var b = AutoplayState()
        b.mouse(at: t)
        _ = b.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(10))
        XCTAssertTrue(b.episodeStarted(autoplayed: true, windowKey: false, at: t.addingTimeInterval(20)), "the window is not in front: the mouse does not count")
    }

    func testTwoQuickKeepWatchingAnswersMakeTheNextAskWaitFourEpisodes() {
        var a = AutoplayState()
        func ask() -> Bool { a.episodeStarted(autoplayed: true, windowKey: false) }
        XCTAssertFalse(ask()); XCTAssertTrue(ask())
        a.answered(keep: true, afterSecs: 4)
        XCTAssertFalse(ask()); XCTAssertTrue(ask())
        a.answered(keep: true, afterSecs: 6)                 // second quick answer in a row
        XCTAssertFalse(ask()); XCTAssertFalse(ask()); XCTAssertFalse(ask())
        XCTAssertTrue(ask(), "the 4th autoplayed episode")
        a.answered(keep: true, afterSecs: 30)
        XCTAssertFalse(ask()); XCTAssertTrue(ask(), "back to 2 episodes")
    }

    func testASlowAnswerBreaksTheQuickRun() {
        var a = AutoplayState()
        func ask() -> Bool { a.episodeStarted(autoplayed: true, windowKey: false) }
        _ = ask(); XCTAssertTrue(ask()); a.answered(keep: true, afterSecs: 3)
        _ = ask(); XCTAssertTrue(ask()); a.answered(keep: true, afterSecs: 40)
        _ = ask(); XCTAssertTrue(ask(), "one quick, one slow: still every 2 episodes")
    }

    func testAnEpisodeStartedByHandIsNotCounted() {
        var a = AutoplayState()
        _ = a.episodeStarted(autoplayed: true, windowKey: false)
        XCTAssertFalse(a.episodeStarted(autoplayed: false, windowKey: false))
        XCTAssertFalse(a.episodeStarted(autoplayed: true, windowKey: false), "the hand-started episode restarted the count")
    }

    func testSeasonAndEpisodeNumbersComeFromTheItemName() {
        XCTAssertEqual(PlayerFormat.seasonEpisode("House of Guinness · S1 E3")?.season, "1")
        XCTAssertEqual(PlayerFormat.seasonEpisode("House of Guinness · S2 E10")?.episode, 10)
        XCTAssertNil(PlayerFormat.seasonEpisode("The Sand Castle"))
        XCTAssertEqual(PlayerFormat.clock(634), "10:34")
        XCTAssertEqual(PlayerFormat.clock(3723), "1:02:03")
    }
}
