import XCTest

/// Player on the real provider (one stream): the labelled bar, the episode strip, the compact card at the credits cue, the chained next episode from Continue watching, audio formats, remembered audio.
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

    // (1) the bar: round buttons, then Audio <language>, Subtitles <language>, and on the right Episodes n of m
    func testBarIsLabelled() {
        launch(["-NXPlay", "film:1773307:mkv", "-NXName", "The Sand Castle", "-NXStart", "600000"])
        press(.select, wait: 2)
        shot("p-1-bar")
        for name in ["Back 10 seconds", "Pause", "Forward 10 seconds", "Audio", "Subtitles"] {
            XCTAssertTrue(app.buttons[name].exists, "\(name) button")
        }
        XCTAssertFalse(app.buttons["Episodes"].exists, "a film has no Episodes button")
    }

    // (2) Episodes n of m opens the strip by focus; Down, Right, OK plays the next episode
    func testEpisodesStripPlaysNext() {
        launch(episode(at: 600_000))
        press(.select, wait: 2)
        press(.right, 5, wait: 2)
        shot("p-2-strip")
        XCTAssertEqual(focused.label, "Episodes", "Episodes has focus and its strip is up")
        press(.down, wait: 1); press(.right, wait: 1)
        press(.select, wait: 25)
        press(.up, wait: 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'E2'")).count > 0, "episode 2 plays")
    }

    // (3a) the compact card shows at the credits cue (no memory, no subtitles read: the last 2 %), waits without a ring on a first episode
    func testEndCardAtTheCue() {
        launch(episode(at: 3_105_000), wait: 14)
        let card = app.buttons["Next episode card"]
        XCTAssertTrue(card.waitForExistence(timeout: 40), "the end card shows near the end")
        shot("p-3-card")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'NEXT'")).count > 0, "NEXT · E2")
        idle(14)
        XCTAssertTrue(card.exists, "the first episode of a session has no ring: the card waits")
    }

    // (3b) OK plays the next episode now
    func testEndCardSelectPlaysNow() {
        launch(episode(at: 3_105_000), wait: 14)
        XCTAssertTrue(app.buttons["Next episode card"].waitForExistence(timeout: 40), "card")
        press(.select, wait: 14)
        press(.up, wait: 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'E2'")).count > 0, "OK plays the next episode now")
    }

    // (3c) Back keeps the credits; the card comes back when the file ends
    func testEndCardBackKeepsCredits() {
        launch(episode(at: 3_105_000), wait: 14)
        XCTAssertTrue(app.buttons["Next episode card"].waitForExistence(timeout: 40), "card")
        press(.menu, wait: 1)
        XCTAssertFalse(app.buttons["Next episode card"].exists, "Back hides the card")
        shot("p-3-kept-watching")
        XCTAssertTrue(app.buttons["Next episode card"].waitForExistence(timeout: 90), "the card returns at the end of the file")
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
