import XCTest

/// Player parity with the Frame (build 9): icon-only controls, Next episode above the timeline, the
/// next-episode card near the end, the chained next episode from Continue watching, audio formats, remembered audio.
final class PlayerParityTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
    func launch(_ args: [String], wait: Double = 22) { app = XCUIApplication(); app.launchArguments = ["-NXMetrics", "YES"] + args; app.launch(); idle(wait) }
    /// House Of Guinness S1 E1 (about 53 min), from its series: the next episodes are found by the player.
    func episode(at ms: Int) -> [String] {
        ["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness", "-NXStart", "\(ms)", "-NXResetUser", "YES"]
    }

    // (1) icons only: no text on the control bar, every button still has a name
    func testControlsAreIcons() {
        launch(["-NXPlay", "film:1773307:mkv", "-NXName", "The Sand Castle", "-NXStart", "600000"])
        press(.select, wait: 2)
        shot("p-1-icons")
        for name in ["Back 10 seconds", "Pause", "Forward 10 seconds", "Audio", "Subtitles"] {
            XCTAssertTrue(app.buttons[name].exists, "\(name) button")
        }
        let texts = app.staticTexts.matching(NSPredicate(format: "label IN {'10 s', 'Audio', 'Subtitles', 'Next episode'}")).count
        XCTAssertEqual(texts, 0, "no text labels on the control bar")
    }

    // (2) Next episode sits above the timeline on the right: Up from the bar reaches it
    func testNextEpisodeAboveTimeline() {
        launch(episode(at: 600_000))
        press(.select, wait: 2)                                // control bar, focus on play/pause
        press(.up, wait: 1)
        shot("p-2-next-button")
        XCTAssertEqual(focused.label, "Next episode", "Up from the bar reaches Next episode")
        let next = app.buttons["Next episode"].frame, pause = app.buttons["Pause"].frame
        XCTAssertGreaterThan(next.minX, 1400, "on the right")
        XCTAssertLessThan(next.maxY, pause.minY, "above the bar (and the timeline)")
    }

    // (3a) the card shows 40 s before the end, counts down and plays the next episode
    func testCountdownPlaysNextEpisode() {
        launch(episode(at: 3_105_000), wait: 14)
        let card = app.staticTexts["NEXT EPISODE"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the next-episode card shows near the end")
        shot("p-3-card")
        XCTAssertTrue(focused.label.hasPrefix("Play now"), "Play now has focus; at \(focused.label)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'S1 E2'")).count > 0, "next episode label S1 E2 · title")
        idle(16)                                               // the 10 s countdown runs out
        press(.up, wait: 1)
        shot("p-3-next-playing")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "episode 2 plays after the countdown")
    }

    // (3b) Select plays now
    func testCountdownSelectPlaysNow() {
        launch(episode(at: 3_105_000), wait: 14)
        XCTAssertTrue(app.staticTexts["NEXT EPISODE"].waitForExistence(timeout: 30), "card")
        press(.select, wait: 12)
        press(.up, wait: 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "Select plays the next episode now")
    }

    // (3c) Menu hides the card, keeps watching, and the card does not come back in this playback
    func testCountdownMenuKeepsWatching() {
        launch(episode(at: 3_105_000), wait: 14)
        XCTAssertTrue(app.staticTexts["NEXT EPISODE"].waitForExistence(timeout: 30), "card")
        press(.menu, wait: 1)
        XCTAssertFalse(app.staticTexts["NEXT EPISODE"].exists, "Menu hides the card")
        idle(14)
        press(.up, wait: 1)
        shot("p-3-kept-watching")
        XCTAssertFalse(app.staticTexts["NEXT EPISODE"].exists, "shown once per playback")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E1'")).count > 0, "still episode 1")
    }

    // (4) started without its episode list (as from Continue watching): the next one is found
    func testResumedEpisodeHasNext() {
        launch(episode(at: 600_000))
        press(.select, wait: 2)
        XCTAssertTrue(app.buttons["Next episode"].waitForExistence(timeout: 10), "Next episode found from the series")
    }

    // (6) the audio menu shows language and format, with a check on the active track
    func testAudioMenuShowsFormat() {
        launch(["-NXPlay", "film:1945414:mkv", "-NXName", "Audio test", "-NXStart", "300000", "-NXResetUser", "YES"])
        press(.select, wait: 2)
        for _ in 0..<5 { if focused.label == "Audio" { break }; press(.right, wait: 0.6) }
        press(.select, wait: 2)
        shot("p-6-audio-formats")
        let withFormat = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · '")).count
        XCTAssertGreaterThanOrEqual(withFormat, 2, "each track shows its format (e.g. English · AC3)")
        XCTAssertTrue(focused.isSelected, "the active track is marked")
    }

    // (5) the audio choice is remembered for the film and applied when it plays again
    func testAudioRememberedForFilm() {
        launch(["-NXPlay", "film:1945414:mkv", "-NXName", "Audio test", "-NXStart", "300000", "-NXResetUser", "YES"])
        press(.select, wait: 2)
        for _ in 0..<5 { if focused.label == "Audio" { break }; press(.right, wait: 0.6) }
        press(.select, wait: 2)
        let first = focused.label
        press(.down, wait: 1); if focused.label == first { press(.up, wait: 1) }
        let picked = focused.label
        press(.select, wait: 4)
        app.terminate()
        launch(["-NXPlay", "film:1945414:mkv", "-NXName", "Audio test", "-NXStart", "300000"], wait: 26)
        press(.select, wait: 2)
        for _ in 0..<5 { if focused.label == "Audio" { break }; press(.right, wait: 0.6) }
        press(.select, wait: 2)
        shot("p-5-remembered")
        XCTAssertEqual(focused.label, picked, "the remembered track is the current one when the film plays again")
    }
}
