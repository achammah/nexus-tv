import XCTest

/// Drives the app with the Siri Remote (XCUIRemote), one journey per test, and saves screenshots
/// to $SHOTS_DIR (scripts/uitest.sh sets it to appletv/shots/remote). Each test opens the app on its screen
/// with launch arguments, then uses only remote presses.
final class RemoteJourneyTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }

    func launch(_ args: [String] = [], wait: Double = 8) {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = (args.contains("-NXTab") ? [] : ["-NXTab", "home"]) + args
        app.launch()
        idle(wait)
    }
    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    func hold(wait: Double = 2) { r.press(.select, forDuration: 1.2); idle(wait) }
    func focused(_ label: String) -> Bool { app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND hasFocus == true", label)).count > 0 }
    var focusedLabel: String { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label }
    /// Picks the n-th item (0 = first) of an open context menu.
    func pickMenu(_ n: Int) {
        if n > 0 { press(.down, n, wait: 0) }
        press(.select, wait: 2)
    }

    // 1-3, 4: Home order, hero Left/Right, country rows with All tile, favourite via long press, header hides
    func test1_HomeRowsFavouritesHero() {
        launch(["-NXResetLayout", "YES", "-NXResetUser", "YES"], wait: 12)
        shot("h1-home")
        press(.down)
        XCTAssertTrue(focused("Watch"), "down from the menu lands on Watch")
        let t0 = app.staticTexts.element(boundBy: 0).label
        press(.left, wait: 2)                                  // Left on Watch: previous featured title
        shot("h2-hero-left")
        let title = { () -> [String] in self.app.staticTexts.allElementsBoundByIndex.map(\.label) }
        XCTAssertNotEqual(t0, "", "hero has text")
        press(.down, wait: 2)                                  // first row: Belgium (no Continue/My List yet)
        shot("h3-belgium-row")
        press(.right, 2, wait: 1)                              // third channel
        hold()                                                 // long press: tile menu
        shot("h4-tile-menu")
        pickMenu(0)                                            // Add to Favourites
        press(.left, 4, wait: 2)                               // the favourite is now the first tile, with a star
        shot("h5-favourite-first")
        press(.right, 30, wait: 2)                             // end of the row
        shot("h5b-all-channels-tile")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All Belgium channels'")).count > 0, "Belgium row ends with All channels")
        press(.left, 30, wait: 1)
        press(.down, 3, wait: 2)
        shot("h6-scrolled-header-hidden")
        _ = title
    }

    // Move one tile inside its row: it lifts and wiggles, left/right slide it, click drops it; "Move" is first in the menu
    func test2_HomeMoveTile() {
        launch(["-NXResetLayout", "YES", "-NXResetUser", "YES"], wait: 12)
        press(.down); press(.down, wait: 2)                    // Belgium row, first tile
        let focusedEl = { self.app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
        let x0 = focusedEl().frame.minX
        hold()
        shot("m0-menu-move-first")
        pickMenu(0)                                            // Move
        shot("m1-tile-lifted")
        press(.right, wait: 1)
        press(.right, wait: 1)
        shot("m2-tile-slid")
        press(.select, wait: 2)                                // drop
        shot("m3-tile-dropped")
        let label = focusedEl().label, x1 = focusedEl().frame.minX
        press(.left, wait: 1)                                  // the moved tile is no longer first: Left reaches another tile
        XCTAssertTrue(focusedEl().label != label || focusedEl().frame.minX < x1, "a tile now sits left of the moved one")
        _ = x0
    }

    // 5, 7, 8, 9: Continue watching from the start, live scrub, control bar, audio picker, back to the detail
    func test3_FilmPlayerControls() {
        launch(["-NXOpen", "film:1773307:The Sand Castle", "-NXResetUser", "YES"], wait: 8)
        shot("f1-film-detail")
        press(.select, wait: 0)                                // Play
        idle(0.6)
        shot("f2-loading-card")
        idle(20)
        press(.right, wait: 0); press(.right, wait: 0); press(.right, wait: 0)   // scrub forward, faster when repeated
        shot("f3-scrub")
        idle(4)                                               // a pause jumps there and plays
        shot("f3b-after-scrub-playing")
        press(.select, wait: 2)                                // control bar
        shot("f4-control-bar")
        press(.right, 2, wait: 1)                              // Audio
        press(.select, wait: 2)
        shot("f5-audio-panel")
        press(.menu, wait: 1)                                  // close the audio panel
        XCTAssertTrue(app.buttons["Subtitles"].exists, "Menu closes the panel and keeps the player")
        press(.menu, wait: 1)                                  // close the control bar
        press(.menu, wait: 3)                                  // leave the player: back on the detail page
        shot("f6-back-on-detail")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume'")).count > 0, "detail offers Resume")
        press(.menu, wait: 3)                                  // Home
        shot("f7-home-continue")
        XCTAssertTrue(app.staticTexts["Continue watching"].exists, "Continue watching row on Home")
        XCTAssertTrue(app.staticTexts["Belgium"].exists || app.staticTexts["New films"].exists, "Home rows drawn after the player")
    }

    // 5 (one per series), 8 (Next episode)
    func test4_SeriesNextEpisode() {
        launch(["-NXOpen", "series:45370", "-NXResetUser", "YES"], wait: 10)
        press(.down, 2, wait: 1)                               // episode 1
        press(.select, wait: 25)
        press(.select, wait: 2)                                // control bar
        shot("s1-episode-controls")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next episode'")).count > 0, "Next episode button")
        press(.right, 4, wait: 1)                              // Next episode
        press(.select, wait: 20)
        press(.up, wait: 1)
        shot("s2-next-episode")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "episode 2 plays")
        press(.menu, wait: 3); press(.menu, wait: 3)
        shot("s3-home-one-entry-per-series")
    }

    // 10: live zap from the guide; favourite from the channel menu
    func test5_LiveGuideFavouriteZap() {
        launch(["-NXTab", "live", "-NXResetUser", "YES"])
        press(.down, 2)
        press(.right, wait: 2)
        press(.down, 2, wait: 2)
        hold()
        shot("l1-channel-menu")
        pickMenu(0)                                            // Add to Favourites: a star in the list
        shot("l2-channel-starred")
        press(.select, wait: 15)                               // play
        press(.left, wait: 1)
        shot("l3-live-playing")
        press(.down, wait: 12)                                 // next channel
        press(.left, wait: 1)
        shot("l4-live-zapped")
        press(.menu, wait: 2)
        shot("l5-back-in-guide")
        press(.right, wait: 1)
        shot("l6-preview-buttons")
    }

    // (search typing on the system search screen: Build4Tests.testNativeSearchEveryLanguage)

    /// Moves focus with one direction until a button whose label starts with `label` has it.
    func focusTo(_ label: String, _ dir: XCUIRemote.Button, max: Int = 10) {
        for _ in 0..<max {
            if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND hasFocus == true", label)).count > 0 { return }
            press(dir, wait: 0); idle(0.4)
        }
        XCTFail("could not focus \(label); focused: \(focusedLabel)")
    }

    // Settings: edit order, lists, accounts (empty form refused), clear lists
    func test7_SettingsListsAccounts() {
        launch(["-NXTab", "settings", "-NXResetLayout", "YES"])
        press(.down, wait: 1)
        focusTo("Menu tabs", .up)
        press(.right, wait: 1)
        focusTo("Edit order", .up)
        press(.select, wait: 1)
        shot("t1-edit-order")
        press(.select, wait: 1)                                // Done
        press(.left, wait: 1)
        focusTo("Lists", .down)
        press(.right, wait: 1)
        focusTo("Browse all lists", .up)
        press(.select, wait: 3)
        shot("t2-list-picker")
        press(.down, 2, wait: 1); press(.select, wait: 2)      // a category from the account (select toggles: on Home afterwards)
        if !focusedLabel.hasPrefix("✓") { press(.select, wait: 2) }
        shot("t3-list-added")
        press(.menu, wait: 2)
        shot("t4-lists")
        press(.left, wait: 1)
        focusTo("Accounts", .down)
        press(.right, wait: 1)
        focusTo("Add an account", .up)
        press(.select, wait: 2)
        focusTo("Cancel", .down)
        press(.left, wait: 1)                                  // Check and save
        press(.select, wait: 2)
        shot("t5-account-form-refused")
        XCTAssertTrue(app.staticTexts["Server, username and password are all needed."].exists, "an empty account is refused")
        press(.menu, wait: 2)
        press(.left, wait: 1)
        focusTo("Clear lists", .down)
        shot("t6-clear")
    }

    // Search covers the lists added in Settings (test 7 adds a 4K Relax live category)
    func test8_SearchCoversAddedLists() {
        launch(["-NXTab", "search", "-NXSearch", "relax"], wait: 14)
        shot("q2-search-lists")
        XCTAssertTrue(app.staticTexts["Channels"].exists, "channels found through the added list")
    }

    // Auto-play: an episode started 30 s before its end goes on to the next one by itself
    func test9_AutoPlayNextEpisode() {
        launch(["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness",
                "-NXStart", "3140000", "-NXResetUser", "YES"], wait: 70)
        press(.up, wait: 1)
        shot("n1-next-episode-autoplay")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'S1 E2'")).count > 0, "episode 2 started by itself")
        press(.menu, wait: 2)
    }

    // Subtitles: the picker lists Off and the file's tracks; picking one turns it on
    func test10_SubtitlesPicker() {
        launch(["-NXPlay", "film:1773307:mkv", "-NXName", "The Sand Castle", "-NXStart", "600000"], wait: 25)
        press(.select, wait: 2)                                // control bar, focus on play/pause
        press(.right, 3, wait: 1)                              // Subtitles
        press(.select, wait: 2)
        shot("c1-subtitles-panel")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Off'")).count > 0, "subtitles panel with Off")
        press(.down, wait: 1); press(.select, wait: 6)         // first track
        shot("c2-subtitles-on")
        press(.menu, wait: 1); press(.menu, wait: 2)
    }

    /// From anywhere in Settings: the Accounts section, focus in its pane.
    func goAccounts() {
        press(.left, 2, wait: 1)
        focusTo("Accounts", .down)
        press(.right, wait: 1)
    }

    /// Types into a system text field: click opens the tvOS keyboard, text is entered, Menu returns.
    func type(_ text: String) {
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "hasFocus == true")).count + app.secureTextFields.matching(NSPredicate(format: "hasFocus == true")).count > 0, "a text field has focus")
        press(.select, wait: 2); app.typeText(text); idle(1); press(.menu, wait: 2)
    }

    // Accounts: a wrong login is refused; a second account is added, switched to, switched back from, and removed
    func test11_SecondAccount() {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["NX_SERVER"], let user = env["NX_USER"], let pass = env["NX_PASS"] else { XCTFail("NX_* not set"); return }
        launch(["-NXTab", "settings"])
        press(.down, wait: 1)
        focusTo("Accounts", .down)
        press(.right, wait: 1); focusTo("Add an account", .up)
        // 1. wrong login (real server, wrong user): refused, nothing saved
        press(.select, wait: 2)
        type("Wrong login"); press(.down, wait: 1)
        type(server); press(.down, wait: 1)
        type("nexus-wrong-user"); press(.down, wait: 1)
        type("wrong-password")
        focusTo("Cancel", .down); press(.left, wait: 1); press(.select, wait: 8)
        // private capture (the form shows the typed server): kept out of shots/, only its status line is read
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/../../build/private-form.png"))
        XCTAssertTrue(app.staticTexts["The provider refused this login."].exists, "a wrong login is refused")
        press(.right, wait: 1); press(.select, wait: 2)        // Cancel
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wrong login'")).count > 0, "the refused account was not saved")
        // 2. a valid second account
        goAccounts(); focusTo("Add an account", .up); press(.select, wait: 2)
        type("Second"); press(.down, wait: 1)
        type(server); press(.down, wait: 1)
        type(user); press(.down, wait: 1)
        type(pass)
        focusTo("Cancel", .down); press(.left, wait: 1); press(.select, wait: 8)
        goAccounts()
        shot("a1-accounts-two")                                 // names only, no login values on screen
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Second'")).count > 0, "second account saved")
        // 3. switch to it, then back
        focusTo("Second", .down); press(.select, wait: 15)
        shot("a2-second-active")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Second' AND label CONTAINS 'Active'")).count > 0, "Second is active")
        focusTo("My IPTV", .up); press(.select, wait: 15)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My IPTV' AND label CONTAINS 'Active'")).count > 0, "switched back to the first account")
        // 4. remove the second one (long press)
        focusTo("Second", .down); hold(); pickMenu(0)
        shot("a3-second-removed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Second'")).count > 0, "second account removed")
    }
}
