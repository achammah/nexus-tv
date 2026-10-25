import XCTest

/// Player redesign (2026-10-25) on the simulator, with no provider stream: the player plays a local file
/// (-NXLocalFile, env NX_LOCAL) and a made-up series (-NXDemoSeries). The file has 6 audio tracks (English 5.1,
/// English description, German twice, Japanese original, one untagged) and 5 subtitle tracks.
final class PlayerRedesignTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.6) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
    func btn(_ label: String) -> Bool { app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).count > 0 }
    func has(_ label: String) -> Bool { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).count > 0 }

    func launch(start: Int, episode: Int = 3, extra: [String] = [], wait: Double = 14) {
        let file = ProcessInfo.processInfo.environment["NX_LOCAL"] ?? ""
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXResetAccounts", "YES", "-NXResetUser", "YES",
                               "-NXPlay", "episode:demo\(episode):mkv", "-NXName", "House Of Guinness · S1 E\(episode)",
                               "-NXSeries", "demo:House Of Guinness", "-NXStart", "\(start)",
                               "-NXLocalFile", file, "-NXDemoSeries", "YES"] + extra
        app.launch(); idle(wait)
    }

    // bar: labelled buttons, header, times
    func testBarAndPopups() {
        launch(start: 100_000)
        press(.select, wait: 2)
        shot("01-bar")
        for n in ["Back 10 seconds", "Pause", "Forward 10 seconds", "Audio", "Subtitles", "Episodes"] { XCTAssertTrue(app.buttons[n].exists, "\(n) button") }
        XCTAssertTrue(has("E3 · Black Velvet"), "header: episode and title")
        XCTAssertEqual(app.buttons["Episodes"].value as? String, "3 of 8", "Episodes n of m")
        XCTAssertEqual(app.buttons["Audio"].value as? String, "English", "Audio <language>")
        // audio popup
        press(.right, 2, wait: 0.5)
        XCTAssertEqual(focused.label, "Audio")
        press(.select, wait: 1.5)
        shot("02-audio-popup")
        for n in ["English", "English · Descriptive", "German", "Japanese · Original", "Track 6"] { XCTAssertTrue(app.buttons[n].exists, "audio row \(n)") }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label MATCHES '(English|German|Japanese) [0-9]'")).count > 0, "never 'English 1'")
        press(.menu, wait: 1)
        // subtitles popup
        press(.right, wait: 0.5)
        press(.select, wait: 1.5)
        shot("03-subtitles-popup")
        for n in ["Off", "English", "English · SDH", "English · Forced", "French", "Dutch"] { XCTAssertTrue(app.buttons[n].exists, "subtitle row \(n)") }
        press(.down, wait: 0.5)                                  // English
        press(.select, wait: 1.5)
        XCTAssertEqual(app.buttons["Subtitles"].value as? String, "English", "Subtitles <language>")
        press(.select, wait: 1.5)                                // the bar button is focused again: reopen the popup
        shot("03b-subtitles-timing")
        XCTAssertTrue(app.buttons["Auto"].exists && app.buttons["Earlier −0.5 s"].exists && app.buttons["Later +0.5 s"].exists, "timing row")
    }

    // strip: focusing Episodes slides it up; Down enters on the playing card; Right then OK plays E4
    func testEpisodeStrip() {
        launch(start: 100_000)
        press(.select, wait: 1)
        press(.right, 5, wait: 1.5)
        XCTAssertEqual(focused.label, "Episodes")
        shot("04-strip")
        XCTAssertTrue(btn("E3 · Black Velvet") && btn("E4 · The Dublin Trade"), "strip cards")
        press(.down, wait: 1)
        XCTAssertTrue(focused.label.contains("Black Velvet"), "Down enters on the playing card: \(focused.label)")
        press(.right, wait: 0.5)
        XCTAssertTrue(focused.label.contains("Dublin Trade"), "Right is the next: \(focused.label)")
        shot("05-strip-focus-next")
        press(.left, wait: 0.5)
        press(.up, wait: 1)
        XCTAssertEqual(focused.label, "Episodes", "Up closes the strip and returns to Episodes")
        shot("05b-after-up")
        XCTAssertFalse(btn("The Dublin Trade"), "strip closed")
        press(.down, wait: 1.5)                                  // the strip is closed: Down from Episodes opens nothing new
        press(.left, wait: 0.5); press(.right, wait: 1.5)        // focus away and back reopens it
        press(.down, wait: 1)
        press(.right, wait: 0.5)
        press(.select, wait: 14)
        press(.select, wait: 2)
        XCTAssertTrue(has("E4 · The Dublin Trade"), "OK plays E4")
    }

    // end card: at the cue; without a chain there is no ring; Back keeps the credits and the card returns at the end
    func testEndCard() {
        launch(start: 270_000)
        let card = app.buttons["Next episode card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "end card shows at the credits cue")
        shot("06-endcard")
        XCTAssertTrue(has("NEXT · E4"), "kicker names the next episode")
        XCTAssertTrue(has("OK plays now"), "hint")
        idle(12)
        XCTAssertTrue(card.exists, "no ring on the first episode: the card waits")
        press(.menu, wait: 1)
        XCTAssertFalse(card.exists, "Back hides the card")
        XCTAssertTrue(card.waitForExistence(timeout: 40), "the card returns when the file ends")
        shot("07-endcard-after-credits")
    }
}

/// Long press on a series tile (Home: Continue watching and My List rows), on the made-up series.
final class SeriesMenuTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.6) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }

    func testLongPressOnSeries() {
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXResetUser", "YES", "-NXDemoSeries", "YES", "-NXResetLayout", "YES", "-NXOnboardSkip", "YES"]
        app.launch(); idle(8)
        shot("10-home")
        press(.down, 1, wait: 1)                       // from the header or hero to the first row
        for _ in 0..<4 where !focused.label.contains("House Of Guinness") { press(.down, wait: 1) }
        XCTAssertTrue(focused.label.contains("House Of Guinness"), "a series tile has focus: \(focused.label)")
        r.press(.select, forDuration: 1.2); idle(1.5)
        shot("11-series-menu")
        XCTAssertTrue(app.buttons["Resume 3"].exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume'")).count > 0, "Resume E3")
        for n in ["Open the show", "Go to episode…", "Remove from My List", "Move", "Hide row"] { XCTAssertTrue(app.buttons[n].exists || (n.hasSuffix("My List") && app.buttons["Add to My List"].exists), n) }
        XCTAssertFalse(app.staticTexts["Black Velvet"].exists, "a long press did not open the show page")
        // Go to episode: season chips, episode chips
        press(.down, 2, wait: 0.5)
        XCTAssertEqual(focused.label, "Go to episode…")
        press(.select, wait: 1.5)
        shot("12-series-menu-episodes")
        XCTAssertTrue(app.buttons["Episode 8"].exists && app.buttons["Season 2"].exists, "chips")
        press(.menu, wait: 1)
        XCTAssertTrue(app.buttons["Open the show"].exists, "Back closes the chips only")
        press(.menu, wait: 1)
        XCTAssertFalse(app.buttons["Open the show"].exists, "Back closes the menu")
    }

    func testClickStillOpensTheShow() {
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXResetUser", "YES", "-NXDemoSeries", "YES", "-NXResetLayout", "YES", "-NXOnboardSkip", "YES"]
        app.launch(); idle(8)
        press(.down, 1, wait: 1)
        for _ in 0..<4 where !focused.label.contains("House Of Guinness") { press(.down, wait: 1) }
        press(.select, wait: 3)
        XCTAssertFalse(app.buttons["Open the show"].exists, "a short click does not open the long-press menu")
    }
}

/// The ring and "Still watching?" on 90 s episodes (the credits cue is 20 s before the end): the first episode's card waits,
/// OK plays the next, which reaches its card cleanly and autoplays, and so on; the third autoplay-free episodes ask.
final class StillWatchingTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.6) }; idle(wait) }
    func has(_ label: String) -> Bool { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).count > 0 }

    func launch() {
        let file = ProcessInfo.processInfo.environment["NX_LOCAL90"] ?? ""
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXResetAccounts", "YES", "-NXResetUser", "YES",
                               "-NXPlay", "episode:demo1:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "demo:House Of Guinness",
                               "-NXStart", "55000", "-NXLocalFile", file, "-NXDemoSeries", "YES",
                               "-NXStillWindowSec", "1", "-NXStillSeconds", "8"]
        app.launch(); idle(10)
    }

    /// E1 card waits (no ring) -> OK -> E2 reaches its card with a ring -> E3 autoplays, same -> E4 autoplays: the toast.
    func driveToTheToast() {
        launch()
        XCTAssertTrue(app.buttons["Next episode card"].waitForExistence(timeout: 40), "E1 card")
        idle(12)
        XCTAssertTrue(app.buttons["Next episode card"].exists, "no ring on the first episode: the card waits")
        press(.select, wait: 6)                                   // OK plays E2
        XCTAssertTrue(app.buttons["Next episode card"].waitForExistence(timeout: 90), "E2 card")
        XCTAssertTrue(has("9") || has("8") || has("10"), "the ring counts down on E2")
        shot("20-ring")
        let toast = app.staticTexts["Still watching?"]
        XCTAssertTrue(toast.waitForExistence(timeout: 240), "after two autoplayed episodes with no key, the toast shows at the start of the third")
        shot("21-still-watching")
    }

    func testKeepWatching() {
        driveToTheToast()
        press(.select, wait: 2)                                   // Keep watching has focus
        XCTAssertFalse(app.staticTexts["Still watching?"].exists, "answered")
        idle(10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'E4'")).count > 0 || has("E5"), "playback went on")
    }

    func testNoAnswerPausesAndReleases() {
        driveToTheToast()
        XCTAssertTrue(app.staticTexts["Paused. Press play to continue"].waitForExistence(timeout: 15), "the 8 s counter ran out: the player says it paused")
        XCTAssertFalse(app.staticTexts["Still watching?"].exists, "the toast is gone")
        shot("22-paused")
        press(.playPause, wait: 12)                               // play reopens the released stream where it was
        XCTAssertTrue(has("E4"), "the same episode is back")
    }
}
