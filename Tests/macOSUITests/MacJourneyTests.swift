import XCTest

/// Nexus TV for Mac, driven with the mouse and keyboard. Screenshots of the library window at 1440 x 900 go to
/// $SHOTS_DIR (scripts/mactest.sh: shots/mac/). The first test signs in from a new install; the others reuse it.
final class MacJourneyTests: XCTestCase {
    var app: XCUIApplication!
    /// The test runner is sandboxed on macOS: shots go to its temporary folder, scripts/mactest.sh copies them out.
    var dir: String {
        let d = NSTemporaryDirectory() + "nxshots"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    var env: [String: String] { ProcessInfo.processInfo.environment }

    func launch(_ args: [String] = [], wait: Double = 8) {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-NXWindowSize", "1440x900", "-ApplePersistenceIgnoreState", "YES"] + args
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 20)
        idle(wait)
    }
    func idle(_ s: Double) { _ = XCTWaiter().wait(for: [XCTestExpectation(description: "idle")], timeout: s) }
    /// The library window only (no desktop around it).
    func shot(_ name: String, _ w: XCUIElement? = nil) {
        let win = w ?? app.windows["Nexus TV"].firstMatch
        let s = (win.exists ? win : app.windows.firstMatch).screenshot()
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }
    var library: XCUIElement { app.windows["Nexus TV"].firstMatch }

    // First launch: the account sheet over the empty window; a wrong login is refused; the real one opens Home.
    func test1_FirstLaunchAccount() {
        guard let server = env["NX_SERVER"], let user = env["NX_USER"], let pass = env["NX_PASS"] else { XCTFail("NX_* not set"); return }
        launch(["-NXResetAccounts", "YES", "-NXResetUser", "YES"], wait: 3)
        let ask = app.staticTexts["Add your IPTV account"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "first launch asks for an account")
        XCTAssertFalse(app.buttons["Cancel"].exists, "no way around it")
        func fill(_ n: String, _ s: String, _ u: String, _ p: String) {
            for (id, v) in [("acc-name", n), ("acc-server", s), ("acc-user", u)] {
                let f = app.textFields[id]; f.click(); f.typeKey("a", modifierFlags: .command); f.typeText(v)
            }
            let pw = app.secureTextFields["acc-pass"]; pw.click(); pw.typeKey("a", modifierFlags: .command); pw.typeText(p)
        }
        fill("Wrong", server, "nexus-wrong-user", "wrong-password")
        app.buttons["acc-save"].click()
        let refused = app.staticTexts["The provider refused this login."]
        XCTAssertTrue(refused.waitForExistence(timeout: 20), "a wrong login is refused")
        fill("My IPTV", server, user, pass)
        app.buttons["acc-save"].click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ask)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "the sheet closes after a valid login")
        XCTAssertTrue(app.staticTexts["TOP SERIES"].waitForExistence(timeout: 60), "Home after sign-in")
        idle(6)
    }

    func waitHome() { XCTAssertTrue(app.staticTexts["TOP SERIES"].waitForExistence(timeout: 40), "Home") }
    func side(_ id: String) { let b = app.buttons[id]; XCTAssertTrue(b.waitForExistence(timeout: 10), id); b.click(); idle(2) }

    // Sidebar: every library page, Live TV by country, the account page, Settings, and back / forward
    func test2_SidebarNavigation() {
        launch()
        waitHome()
        side("side:Live TV")
        XCTAssertTrue(app.staticTexts["Countries"].waitForExistence(timeout: 10), "Live TV lists the countries")
        side("side:live:BE")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel:'")).firstMatch.waitForExistence(timeout: 30), "Belgian channels")
        idle(3)
        side("side:Films")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile:film:'")).firstMatch.waitForExistence(timeout: 40), "film posters")
        idle(3)
        side("side:Series")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile:series:'")).firstMatch.waitForExistence(timeout: 40), "series posters")
        idle(3)
        side("side:My List")
        side("side:IPTV account")
        XCTAssertTrue(app.staticTexts["Active"].waitForExistence(timeout: 5), "the active account")
        side("side:Settings")
        XCTAssertTrue(app.staticTexts["Film and series languages"].waitForExistence(timeout: 5), "Settings")
        app.buttons["Back"].click(); idle(1)
        XCTAssertTrue(app.staticTexts["Active"].exists, "Back returns to the account page")
        app.buttons["Forward"].click(); idle(1)
        XCTAssertTrue(app.staticTexts["Film and series languages"].exists, "Forward returns to Settings")
    }

    // Search across everything: the sidebar field (Cmd+F), channels of every country, films of every language
    func test3_Search() {
        launch()
        waitHome()
        app.typeKey("f", modifierFlags: .command); idle(1)
        app.typeText("rtl"); idle(1)
        XCTAssertTrue(app.otherElements["results:Channels"].waitForExistence(timeout: 30) || app.staticTexts["Channels"].waitForExistence(timeout: 5), "channel results")
        XCTAssertTrue(app.staticTexts["Channels · other countries"].waitForExistence(timeout: 120), "channels of other countries")
        idle(2)
        let f = app.textFields["search-field"]; f.click(); f.typeKey("a", modifierFlags: .command); f.typeText("afro samurai")
        XCTAssertTrue(app.staticTexts["Films · other languages"].waitForExistence(timeout: 180) || app.staticTexts["Series · other languages"].exists, "other languages")
    }

    // Film page: poster, facts, Play; series page: episodes with a progress bar for the one being watched
    func test4_FilmAndSeriesPages() {
        launch(["-NXOpen", "film:1773307:The Sand Castle"])
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 20), "Play on the film page")
        idle(3)
        app.terminate()
        // watch 25 s of episode 1 (the resume store saves every 15 s), then the series page
        launch(["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness", "-NXStart", "600000", "-NXResetUser", "YES"], wait: 40)
        app.terminate()
        launch(["-NXOpen", "series:45370:House Of Guinness"])
        let ep = app.buttons["episode:1:1"]
        XCTAssertTrue(ep.waitForExistence(timeout: 30), "episode list")
        XCTAssertTrue(ep.label.contains("watched"), "episode 1 shows its progress; label \(ep.label)")
        XCTAssertFalse(app.buttons["episode:1:2"].label.contains("watched"), "episode 2 has no progress")
        idle(2)
    }

    /// The player plays inside the library window.
    var player: XCUIElement { app.windows.firstMatch }

    // Player window: the controls, keyboard (space, F), picture in picture, next episode with its picture,
    // and the next-episode card near the end
    func test5_PlayerWindow() {
        launch(["-NXPlay", "episode:1928870:mkv", "-NXName", "House Of Guinness · S1 E1", "-NXSeries", "45370:House Of Guinness", "-NXStart", "3090000"], wait: 6)
        XCTAssertTrue(app.descendants(matching: .any)["hud"].waitForExistence(timeout: 30), "the player in the window")
        idle(10)
        player.hover(); idle(1)
        for b in ["Back 10 seconds", "Pause", "Forward 10 seconds", "Picture in picture", "Full screen", "Next episode"] {
            XCTAssertTrue(player.buttons[b].exists, b)
        }
        XCTAssertTrue(player.menuButtons["Audio"].exists || player.popUpButtons["Audio"].exists || player.descendants(matching: .any)["audio-menu"].exists, "audio menu")
        XCTAssertTrue(player.descendants(matching: .any)["cc-menu"].exists, "CC menu")
        player.typeKey(" ", modifierFlags: []); idle(1)
        XCTAssertTrue(player.buttons["Play"].exists, "space pauses")
        player.typeKey(" ", modifierFlags: []); idle(1)
        let w0 = player.frame.width
        player.buttons["Picture in picture"].click(); idle(2)
        XCTAssertLessThan(player.frame.width, w0 * 0.6, "picture in picture: a small window")
        player.hover(); idle(1)
        player.buttons["Leave picture in picture"].click(); idle(2)
        XCTAssertGreaterThan(player.frame.width, w0 * 0.8, "back to the window size")
        let card = player.descendants(matching: .any)["up-next"]
        XCTAssertTrue(card.waitForExistence(timeout: 60), "next-episode card near the end")
        player.buttons["play-now"].click(); idle(15)
        XCTAssertTrue(app.staticTexts["player-title"].label.contains("Episode 2"), "episode 2 plays")
        player.typeKey("f", modifierFlags: []); idle(3)
        player.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); idle(3)
    }

    // Play from a film page: it plays inside the same window; Esc returns to that film page
    func test6_PlayInWindowEscReturns() {
        launch(["-NXOpen", "film:1773307:The Sand Castle"])
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Play on the film page")
        let windows = app.windows.count
        play.click()
        XCTAssertTrue(app.descendants(matching: .any)["hud"].waitForExistence(timeout: 20), "the player's control bar")
        XCTAssertEqual(app.windows.count, windows, "no new window: the film plays in the library window")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); idle(2)
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 5), "Esc returns to the film page")
    }

    /// Texts on the page that still carry a language tag (the old flat list showed "Drama · EN").
    func taggedRows() -> [String] {
        app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.hasSuffix("· EN") || $0.hasSuffix("· FR") }
    }

    // Films: shelves by family, Streaming services first; no row text ends with " · EN"; a service opens its lists,
    // a list opens its posters; Back returns.
    func test7_FilmsShelvesByFamily() {
        launch(["-NXPage", "films"], wait: 12)
        XCTAssertTrue(app.descendants(matching: .any)["shelf:Streaming services"].waitForExistence(timeout: 20), "the Streaming services shelf")
        XCTAssertTrue(app.descendants(matching: .any)["shelf:Genres"].exists, "the Genres shelf")
        XCTAssertEqual(taggedRows(), [], "no list name ends with a language tag")
        XCTAssertTrue(app.descendants(matching: .any)["language-menu"].exists, "one Language menu for the page")
        let netflix = app.buttons["card:Netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 10), "the Netflix service card")
        netflix.click(); idle(3)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card:'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "the lists inside Netflix")
        first.click(); idle(6)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile:'")).firstMatch.waitForExistence(timeout: 20), "the list's posters")
        app.buttons["Back"].click(); idle(2)
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Back returns to the service's lists")
    }

    // Series: the same shelves; "Show N small lists" reveals the hidden ones.
    func test8_SeriesShelvesAndSmallLists() {
        launch(["-NXPage", "series"], wait: 12)
        XCTAssertTrue(app.descendants(matching: .any)["shelf:Streaming services"].waitForExistence(timeout: 20), "the Streaming services shelf")
        XCTAssertEqual(taggedRows(), [], "no list name ends with a language tag")
        let small = app.buttons["small-lists"]
        if small.waitForExistence(timeout: 5) {
            small.click(); idle(1)
            XCTAssertTrue(app.descendants(matching: .any)["shelf:Small lists"].waitForExistence(timeout: 5), "small lists shown on demand")
        }
    }

    // Live TV of a country: family shelves, events and pay-per-view last; a list opens its channels.
    func test9_LiveCountryShelves() {
        launch(["-NXPage", "live:US"], wait: 20)
        XCTAssertTrue(app.descendants(matching: .any)["shelf:Main channels"].waitForExistence(timeout: 30), "the Main channels shelf")
        let shelves = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'shelf:'")).allElementsBoundByIndex.map(\.identifier)
        if shelves.contains("shelf:Events & pay-per-view") { XCTAssertEqual(shelves.last, "shelf:Events & pay-per-view", "events last") }
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'group:'")).firstMatch.exists, "no flat group list")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card:'")).firstMatch
        card.click(); idle(6)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel:'")).firstMatch.waitForExistence(timeout: 20), "the list's channels")
    }
}
