import XCTest

/// Live realignment on a real stream: an online subtitle not made for this file is put in sync by itself, with no
/// press, against the file's own subtitle track. The offset the app found is written to $SHOTS_DIR/realign-tvos.txt;
/// scripts/realign_check.py measures the true offset from the same two files and compares.
final class RealignTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
    func focusTo(_ label: String, _ dir: XCUIRemote.Button, max: Int = 12) -> Bool {
        for _ in 0..<max { if focused.label.contains(label) { return true }; press(dir, wait: 0.5) }
        return focused.label.contains(label)
    }
    func openSubtitles() {
        let bar: Set<String> = ["Back 10 seconds", "Pause", "Play", "Forward 10 seconds", "Audio", "Subtitles", "Next episode", "Episodes"]
        if !bar.contains(focused.label) { press(.select, wait: 2) }
        XCTAssertTrue(focusTo("Subtitles", .right), "Subtitles button")
        press(.select, wait: 2)
    }
    var timing: String { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Timing'")).firstMatch.label }

    func testOnlineSubtitleAlignsByItself() {
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXPlay", "film:2163590:mkv", "-NXName", "Spider-Man Brand New Day", "-NXStart", "900000",
                               "-NXResetUser", "YES", "-NXResetSubDelay", "YES", "-NXSubDelayStart", "6000"]
        app.launch(); idle(24)
        openSubtitles()
        let fr = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'French · online'")).firstMatch
        XCTAssertTrue(fr.waitForExistence(timeout: 25), "a French online subtitle")
        for _ in 0..<40 { if focused.label.hasPrefix("French · online") { break }; press(.down, wait: 0.3) }
        let picked = focused.label
        press(.select, wait: 6)
        openSubtitles()
        XCTAssertTrue(app.buttons["Later +0.5 s"].waitForExistence(timeout: 15), "timing rows under the online subtitle")
        let before = timing
        press(.menu, wait: 1)
        idle(100)                                          // dialogue plays; nobody presses anything
        openSubtitles()
        XCTAssertTrue(app.buttons["Later +0.5 s"].waitForExistence(timeout: 15), "timing rows")
        let after = timing
        shot("realign-tvos")
        try? "picked=\(picked)\nbefore=\(before)\nafter=\(after)\n".write(toFile: dir + "/realign-tvos.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(before, "Timing +6.0 s", "the subtitle starts 6 s off")
        let v = Double(after.replacingOccurrences(of: "Timing ", with: "").replacingOccurrences(of: " s", with: "")) ?? 99
        XCTAssertLessThan(abs(v), 1.0, "in sync with no press: the timing came back from +6.0 s to \(after)")
    }
}
