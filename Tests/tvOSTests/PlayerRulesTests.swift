import XCTest
@testable import NexusTV

/// The credits cue (memory median, subtitle quiet, 2 % fallback) and the track label rule, as pure functions.
final class CreditsCueTests: XCTestCase {
    let length = 3_300_000                       // a 55-minute episode

    func testMemoryMedianOfTheLastFive() {
        // six samples: only the last five count (110, 95, 120, 90, 300): the median is 110 s before the end
        let cue = CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [100, 110, 95, 120, 90, 300], cueStartsMs: nil, nowMs: 0)
        XCTAssertEqual(cue, length - 110_000)
        XCTAssertEqual(CreditsCue.median([60, 100]), 80, "an even count averages the two middle samples")
        XCTAssertNil(CreditsCue.median([]))
    }

    func testMemoryOutranksSubtitlesAndTheFallback() {
        let starts = Array(stride(from: 1_000, to: 3_000_000, by: 5_000))
        let cue = CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [150], cueStartsMs: starts, nowMs: 3_100_000)
        XCTAssertEqual(cue, length - 150_000, "the show's own memory comes first")
    }

    func testSubtitleQuiet() {
        let starts = Array(stride(from: 0, through: 3_000_000, by: 5_000))      // dialogue to 50:00, then nothing
        // 50 s of silence inside the last 6 minutes: the cue is where the speech stopped
        XCTAssertEqual(CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [], cueStartsMs: starts, nowMs: 3_050_000), 3_000_000)
        // 30 s of silence is not enough yet: the 2 % rule stays the cue
        XCTAssertEqual(CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [], cueStartsMs: starts, nowMs: 3_030_000), length - 66_000)
        // silence that began before the last 6 minutes counts from the start of that window
        let early = Array(stride(from: 0, through: 2_500_000, by: 5_000))
        XCTAssertEqual(CreditsCue.quietStart(cueStartsMs: early, nowMs: 3_000_000, lengthMs: length), length - 360_000)
        XCTAssertNil(CreditsCue.quietStart(cueStartsMs: early, nowMs: 2_950_000, lengthMs: length), "45 s have not passed inside the window")
    }

    func testTwoPercentFallbackNeverUnderTwentySeconds() {
        XCTAssertEqual(CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [], cueStartsMs: nil, nowMs: 0), length - 66_000, "2 % of 55 min")
        XCTAssertEqual(CreditsCue.cueMs(lengthMs: 600_000, memorySecondsBeforeEnd: [], cueStartsMs: nil, nowMs: 0), 580_000, "2 % of 10 min is 12 s: 20 s")
        XCTAssertEqual(CreditsCue.cueMs(lengthMs: length, memorySecondsBeforeEnd: [], cueStartsMs: [], nowMs: 3_200_000), length - 66_000, "a file with no readable cues")
    }

    func testSamples() {
        XCTAssertEqual(CreditsCue.pressSample(remainingMs: 95_000), 95)
        XCTAssertNil(CreditsCue.pressSample(remainingMs: 9 * 60_000), "a press with over 8 minutes left is not a sample")
        XCTAssertEqual(CreditsCue.endSample(lengthMs: length, lastInteractionMs: length - 200_000, quietPointMs: length - 70_000), 200, "the last key press inside the last 8 minutes")
        XCTAssertEqual(CreditsCue.endSample(lengthMs: length, lastInteractionMs: 100_000, quietPointMs: length - 70_000), 70, "else the quiet point")
        XCTAssertNil(CreditsCue.endSample(lengthMs: length, lastInteractionMs: nil, quietPointMs: nil))
    }

    func testStillWatchingPolicy() {
        var w = StillWatching()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        w.key(t0)
        w.autoplayed(); w.autoplayed()
        XCTAssertFalse(w.shouldAsk(now: t0.addingTimeInterval(60 * 60)), "a key in the last 90 minutes")
        XCTAssertTrue(w.shouldAsk(now: t0.addingTimeInterval(95 * 60)))
        w.key(t0.addingTimeInterval(96 * 60))
        XCTAssertEqual(w.autoplays, 0, "a key press starts the count again")
        // two quick "Keep watching" answers: the next ask waits for four autoplayed episodes
        w.answered(keep: true, after: 4, now: t0); w.answered(keep: true, after: 6, now: t0)
        XCTAssertEqual(w.threshold, 4)
        w.answered(keep: true, after: 30, now: t0)
        XCTAssertEqual(w.threshold, 2, "a slow answer resets it")
    }
}

final class TrackLabelTests: XCTestCase {
    func audio(_ i: Int, _ raw: String, _ lang: String?, _ ch: String?, _ codec: String?) -> TrackFacts {
        TrackFacts(index: i, raw: raw, language: lang, channels: ch, codec: codec)
    }

    func testTaggedTracks() {
        let l = TrackLabels.labels([audio(1, "Track 1 - [English]", "English", "5.1", "AC3"), audio(2, "Track 2 - [Japanese]", "Japanese", "stereo", "AAC")], audio: true)
        XCTAssertEqual(l[1]?.name, "English"); XCTAssertEqual(l[1]?.detail, "5.1 · AC3"); XCTAssertEqual(l[1]?.flag, "flag-gb")
        XCTAssertEqual(l[2]?.name, "Japanese"); XCTAssertEqual(l[2]?.flag, "flag-jp"); XCTAssertEqual(l[2]?.short, "Japanese")
    }

    func testDuplicatesAreToldApartNeverNumbered() {
        let l = TrackLabels.labels([
            audio(1, "Track 1 - [English]", "English", "5.1", "AC3"),
            audio(2, "Audio Description - [English]", "English", "stereo", "AAC"),
            audio(3, "Track 3 - [German]", "German", "5.1", "AC3"),
            audio(4, "Track 4 - [German]", "German", "stereo", "AAC"),
        ], audio: true)
        XCTAssertEqual(l[1]?.name, "English")
        XCTAssertEqual(l[2]?.name, "English · Descriptive", "the title says what it is")
        XCTAssertEqual(l[3]?.name, "German"); XCTAssertEqual(l[3]?.detail, "5.1 · AC3")
        XCTAssertEqual(l[4]?.name, "German"); XCTAssertEqual(l[4]?.detail, "stereo · AAC", "channels and codec tell two German tracks apart")
        for t in l.values { XCTAssertNil(t.name.range(of: "(English|German) [0-9]", options: .regularExpression), "never 'English 1 / English 2'") }
        // a pair identical on every point is the only case that gets a track number, and never a bare digit
        let twins = TrackLabels.labels([audio(1, "x", "French", "stereo", "AAC"), audio(2, "y", "French", "stereo", "AAC")], audio: true)
        XCTAssertEqual(twins[1]?.name, "French · Track 1"); XCTAssertEqual(twins[2]?.name, "French · Track 2")
    }

    func testSubtitleKeywords() {
        let l = TrackLabels.labels([
            TrackFacts(index: 0, raw: "Track 1 - [English]", language: "English"),
            TrackFacts(index: 1, raw: "SDH - [English]", language: "English"),
            TrackFacts(index: 2, raw: "English forced - [English]", language: "English"),
        ], audio: false)
        XCTAssertEqual(l[0]?.name, "English")
        XCTAssertEqual(l[1]?.name, "English · SDH"); XCTAssertEqual(l[1]?.detail, "hearing impaired")
        XCTAssertEqual(l[2]?.name, "English · Forced"); XCTAssertEqual(l[2]?.detail, "signs only")
    }

    func testUntaggedTrack() {
        let l = TrackLabels.labels([audio(1, "Track 1 - [English]", "English", "5.1", "AC3"), audio(6, "Track 6", nil, "stereo", nil)], audio: true)
        XCTAssertEqual(l[6]?.name, "Track 2", "N is the place in the list")
        XCTAssertEqual(l[6]?.detail, "unknown language · stereo")
        XCTAssertNil(l[6]?.flag, "a grey circle")
        XCTAssertEqual(l[6]?.short, "Track 2")
        XCTAssertEqual(TrackLabels.keyword(in: "Track 3"), nil)
    }
}
