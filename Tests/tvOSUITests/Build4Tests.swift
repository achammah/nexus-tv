import XCTest

/// Build 4 journeys: native search across every language, and track choices carried to the next episode.
final class Build4Tests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.45) }; idle(wait) }
    var focusedLabel: String { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label }
    func focusContains(_ text: String, _ dir: XCUIRemote.Button, max: Int = 14) -> Bool {
        for _ in 0..<max {
            if app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND hasFocus == true", text)).count > 0 { return true }
            press(dir, wait: 0); idle(0.3)
        }
        return false
    }

    // Apple's search screen: the keyboard takes focus, letters type, results (incl. other languages) are focusable, select opens one
    func testNativeSearchEveryLanguage() {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "search"]
        app.launch(); idle(12)
        press(.down, wait: 2)                                  // from the menu into the search screen (keyboard)
        shot("s4-1-search-screen")
        let typed = Date()
        app.typeText("afro samurai")
        // the other-language index is built once a day from the full lists; the first run after an update waits for it
        let otherRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Films · other' OR label BEGINSWITH 'Series · other'")).firstMatch
        _ = otherRow.waitForExistence(timeout: 300)
        let wait = Date().timeIntervalSince(typed)
        print(String(format: "NXTIME other-language results %.1f s after typing", wait))
        shot("s4-2-typed")
        let other = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Films · other' OR label BEGINSWITH 'Series · other'")).count
        XCTAssertGreaterThan(other, 0, "results from other languages (Afro Samurai is only in |DE| ANIME)")
        // down past the keyboard into the results
        var reached = false
        for _ in 0..<8 {
            press(.down, wait: 1)
            if app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND elementType == %d", XCUIElement.ElementType.button.rawValue)).count > 0 &&
               !app.keyboards.element.exists { reached = true; break }
        }
        shot("s4-3-result-focused")
        XCTAssertTrue(reached || focusedLabel.lowercased().contains("afro"), "a result has focus; focused: \(focusedLabel)")
        press(.select, wait: 6)
        shot("s4-4-opened")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'afro'")).count > 0, "the result opened")
    }

    // Pick audio + subtitles on an episode, play the next one: both come back without the menu (checked in metrics.log)
    func testTrackChoiceCarriesToNextEpisode() {
        app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1",
                               "-NXSeries", "45370:House Of Guinness", "-NXStart", "120000"]
        app.launch(); idle(25)
        press(.select, wait: 2)                                // control bar, focus on play/pause
        press(.right, 3, wait: 1); press(.select, wait: 2)     // Subtitles panel
        shot("t4-1-subtitles")
        press(.up, 3, wait: 1); press(.select, wait: 3)        // another subtitle track (the choice is logged as player.choose)
        shot("t4-2-subtitles-on")
        press(.up, wait: 1)                                    // focus is back on Subtitles: Next episode is above the bar
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next episode' AND hasFocus == true")).count > 0, "Next episode focused; focused: \(focusedLabel)")
        press(.select, wait: 30)
        press(.up, wait: 1)
        shot("t4-3-next-episode")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "episode 2 playing")
    }

    // Settings › Lists: every category of the account (no cap), tabs, ✓ on Home, select toggles.
    // Settings › Channels: country, group, channel; select stars; a star outside the chosen countries shows in "More favourites".
    func testSettingsBrowseListsAndChannels() {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "settings", "-NXResetLayout", "YES"]
        app.launch(); idle(12)
        press(.down, wait: 1)
        XCTAssertTrue(focusContains("Menu tabs", .up), "Settings sidebar")
        XCTAssertTrue(focusContains("Lists", .down), "Lists section")
        press(.right, wait: 1)
        XCTAssertTrue(focusContains("Browse all lists", .up), "browse button")
        press(.select, wait: 4)
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' categories'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 20))
        shot("l4-1-all-lists")
        let total = Int(String((count.label.components(separatedBy: " of ").last ?? "").prefix { $0 != " " }.filter(\.isNumber))) ?? 0
        XCTAssertGreaterThan(total, 1000, "every category of the account: \(count.label)")
        press(.right, 3, wait: 1); press(.select, wait: 2)     // Films tab
        shot("l4-2-films-tab")
        let films = Int(app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' categories'")).firstMatch.label.components(separatedBy: " ").first ?? "") ?? 0
        XCTAssertTrue(films > 0 && films < total, "Films tab narrows the list: \(films) of \(total)")
        press(.down, wait: 1)
        let before = focusedLabel
        press(.select, wait: 2)
        XCTAssertNotEqual(before.hasPrefix("✓"), focusedLabel.hasPrefix("✓"), "select adds or removes: \(before) -> \(focusedLabel)")
        shot("l4-3-toggled")
        press(.select, wait: 2)                                // back as it was
        press(.menu, wait: 2)
        press(.left, wait: 1)
        XCTAssertTrue(focusContains("Channels", .down), "Channels section")
        press(.right, wait: 1)
        XCTAssertTrue(focusContains("Browse all channels", .up), "browse channels")
        press(.select, wait: 6)
        press(.down, 6, wait: 1)                               // a country down the list (not one of the four chosen)
        let country = focusedLabel
        press(.right, wait: 3)                                 // its groups
        press(.right, wait: 6)                                 // its channels
        shot("l4-4-channel-picker")
        if app.staticTexts["★  Added to Favourites"].exists == false {
            press(.select, wait: 1)
            if app.staticTexts["Removed from Favourites"].exists { idle(3); press(.select, wait: 1) }
        }
        shot("l4-5-starred")
        XCTAssertTrue(app.staticTexts["★  Added to Favourites"].exists || app.images.matching(NSPredicate(format: "label CONTAINS 'Favorite' OR identifier CONTAINS 'star.fill'")).count > 0, "starred (country \(country))")
        press(.menu, wait: 2)
        shot("l4-6-channels-pane")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Browse all channels'")).count > 0, "back on the Channels section after closing")
        app.terminate()
        app.launchArguments = ["-NXTab", "home"]
        app.launch(); idle(14)
        var found = false
        for _ in 0..<10 { if app.staticTexts["More favourites"].exists { found = true; break }; press(.down, wait: 1) }
        shot("l4-7-more-favourites")
        XCTAssertTrue(found, "More favourites row on Home")
    }

    // Search: channels of every other country, with the country code as badge
    func testSearchOtherCountries() {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "search", "-NXSearch", "rtl"]
        app.launch()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Channels · other'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 300), "channels of other countries")
        idle(2)
        press(.down, 3, wait: 2)                               // past the keyboard to the first rows
        shot("s4-4-channels-rows")
        press(.down, 5, wait: 2)
        shot("s4-5-other-countries")
    }
}
