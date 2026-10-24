import XCTest

/// Online subtitles from OpenSubtitles: the account in Settings, results in the CC menu, a pick that shows,
/// and the next episode taking the remembered online choice. Needs OSUB_ACCOUNT_FILE (see scripts/uitest.sh).
final class OSubTests: XCTestCase {
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
    func type(_ text: String) {
        press(.select, wait: 2); app.typeText(text); idle(1); press(.menu, wait: 2)
    }
    func launch(_ args: [String], wait: Double = 12) { app = XCUIApplication(); app.launchArguments = ["-NXMetrics", "YES"] + args; app.launch(); idle(wait) }

    func openSubtitles() {
        let bar: Set<String> = ["Back 10 seconds", "Pause", "Play", "Forward 10 seconds", "Audio", "Subtitles", "Next episode"]
        if !bar.contains(focused.label) { press(.select, wait: 2) }       // the control bar is hidden: show it
        XCTAssertTrue(focusTo("Subtitles", .right), "Subtitles button")
        press(.select, wait: 2)
    }

    // Settings › Subtitles: the account is checked with /login and kept; the pane says who is signed in
    func test1_SignIn() {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["NX_OS_KEY"], let user = env["NX_OS_USER"], let pass = env["NX_OS_PASS"] else { XCTFail("NX_OS_* not set"); return }
        launch(["-NXTab", "settings", "-NXResetOSub", "YES"])
        press(.down, wait: 1)
        XCTAssertTrue(focusTo("Menu tabs", .up), "sidebar")
        XCTAssertTrue(focusTo("Subtitles", .down), "Subtitles section")
        press(.right, wait: 1)
        XCTAssertTrue(focusTo("Add an OpenSubtitles account", .up), "add button")
        press(.select, wait: 2)
        type(key); press(.down, wait: 1)
        type(user); press(.down, wait: 1)
        type(pass); press(.down, wait: 1)
        XCTAssertTrue(focusTo("Check and save", .left), "Check and save")
        press(.select, wait: 8)
        shot("o-1-signed-in")   // names the account user only
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Signed in as'")).count > 0, "signed in")
    }

    // CC menu: embedded tracks, then online results in the owner's languages; a pick shows and is marked
    func test2_CCMenuOnline() {
        launch(["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness",
                "-NXStart", "600000", "-NXResetUser", "YES"], wait: 24)
        openSubtitles()
        let header = app.staticTexts["Online · OpenSubtitles"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "online section in the CC menu")
        let results = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' · online'"))
        let any = results.firstMatch.waitForExistence(timeout: 20)
        shot("o-2-cc-menu")
        XCTAssertTrue(any, "online results listed")
        // pick the first online result
        for _ in 0..<40 { if focused.label.hasSuffix(" · online") { break }; press(.down, wait: 0.3) }
        let picked = focused.label
        press(.select, wait: 8)
        shot("o-2-picked")
        openSubtitles()
        shot("o-2-reopened")
        XCTAssertEqual(focused.label, picked, "the panel reopens on the online subtitle")
        XCTAssertTrue(focused.isSelected, "the online subtitle is marked current")
    }

    // The next episode takes the remembered online choice (its best match in that language) by itself
    func test3_NextEpisodeTakesOnlineChoice() {
        launch(["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness",
                "-NXStart", "600000"], wait: 24)
        // the choice made in test 2 is remembered for the series: episode 1 shows it again
        press(.select, wait: 2)
        press(.up, wait: 1)
        XCTAssertEqual(focused.label, "Next episode", "Next episode")
        press(.select, wait: 30)
        openSubtitles()
        shot("o-3-next-episode")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "episode 2 plays")
        XCTAssertTrue(focused.label.hasSuffix(" · online") && focused.isSelected, "episode 2 shows the online subtitle; at \(focused.label)")
    }
}
