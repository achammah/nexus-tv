import XCTest

/// Switching the audio track: the picked track becomes the current one and playback goes on.
/// Films with several audio tracks on the test account: 287415 (6 tracks), 1945414 (2 tracks).
final class AudioTrackTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }

    /// Track buttons of the open panel (their labels are languages, never a control name).
    var panelOpen: Bool { app.staticTexts.matching(NSPredicate(format: "label == 'Audio'")).count > 0 && !app.buttons["Subtitles"].isHittable }
    func openAudio() {
        if !app.buttons["Audio"].exists { press(.select, wait: 2) }     // show the control bar
        for _ in 0..<5 { if focused.label == "Audio" { break }; press(focused.label.contains("10") || focused.label.isEmpty ? .right : .right, wait: 0.6) }
        XCTAssertEqual(focused.label, "Audio", "Audio button focused")
        press(.select, wait: 2)
    }

    func switchAudio(_ film: String, _ name: String) {
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXPlay", "film:" + film, "-NXName", "Audio test", "-NXStart", "300000", "-NXResetUser", "YES"]
        app.launch(); idle(22)
        openAudio()
        let first = focused.label
        shot("a-\(name)-1-panel")
        press(.down, wait: 1)                                  // another track: the next one, or the one above at the end
        if focused.label == first { press(.up, wait: 1) }
        let target = focused.label
        XCTAssertNotEqual(first, target, "a second audio track exists")
        press(.select, wait: 5)                                // pick it; the panel closes
        shot("a-\(name)-2-picked")
        openAudio()                                            // reopen: it opens on the current track
        shot("a-\(name)-3-reopened")
        XCTAssertEqual(focused.label, target, "the panel reopens on the picked track")
        XCTAssertTrue(focused.isSelected, "the picked track is marked current")
        press(.menu, wait: 1)                                  // close the panel; the bar stays
        // playback goes on: the elapsed time moves
        let clock = NSPredicate(format: "label MATCHES '^[0-9]+:[0-9]{2}(:[0-9]{2})?$'")
        let t1 = app.staticTexts.matching(clock).firstMatch.label
        idle(4)
        if !app.buttons["Audio"].exists { press(.select, wait: 1) }
        let t2 = app.staticTexts.matching(clock).firstMatch.label
        shot("a-\(name)-4-playing")
        XCTAssertNotEqual(t1, t2, "the clock moves after the switch (\(t1) -> \(t2))")
    }

    func testSwitchAudioSixTracks() { switchAudio("287415:mkv", "six") }
    func testSwitchAudioTwoTracks() { switchAudio("1945414:mkv", "two") }
}
