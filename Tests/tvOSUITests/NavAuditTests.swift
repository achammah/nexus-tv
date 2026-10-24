import XCTest

/// Navigation audit: every remote move from every zone reaches its obvious neighbour, never traps.
/// Each step's focused element is written to $SHOTS_DIR/nav-<test>.txt (labels only).
final class NavAuditTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    var trace: [String] = []
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 0.8) {
        for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait)
        trace.append("\(b.rawValue) -> \(where_())")
    }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
    func where_() -> String {
        let f = focused
        guard f.exists else {
            idle(2)   // the header fades in: look again once it is drawn
            let g = focused
            return g.exists ? "\(g.elementType.rawValue):\(g.label.prefix(40)) (late)" : "(nothing)"
        }
        return "\(f.elementType.rawValue):\(f.label.prefix(40))"
    }
    /// Focus is on the search keyboard (the element itself reports focus; its keys do not).
    var onKeyboard: Bool { focused.elementType == .keyboard || app.keys.matching(NSPredicate(format: "hasFocus == true")).count > 0 || app.searchFields.matching(NSPredicate(format: "hasFocus == true")).count > 0 }
    var onMenu: Bool { app.buttons.matching(NSPredicate(format: "hasFocus == true AND (label IN {'Home','Live TV','Films','Series','My List','Search','Settings','gearshape.fill'})")).count > 0 }
    func save(_ name: String) { try? trace.joined(separator: "\n").write(toFile: dir + "/nav-" + name + ".txt", atomically: true, encoding: .utf8) }
    func launch(_ args: [String]) { app = XCUIApplication(); app.launchArguments = args; app.launch(); idle(12) }

    /// Search: type, go Down into row n (after k moves right), then Up must climb back to the keyboard.
    func upFromResults(row n: Int, right k: Int, _ name: String) {
        launch(["-NXTab", "search", "-NXSearch", "rtl"])
        press(.down, wait: 1.5)                                       // menu -> keyboard
        XCTAssertTrue(onKeyboard, "\(name): keyboard focused first; at \(where_())")
        press(.down, n + 1, wait: 1)                                  // into row n
        if k > 0 { press(.right, k, wait: 1) }
        shot("nav-\(name)-1-in-results")
        var back = false
        for _ in 0..<(n + 4) { press(.up, wait: 0.8); if onKeyboard { back = true; break } }
        shot("nav-\(name)-2-after-up")
        if back {   // typing works again from here
            app.typeText("x"); idle(2)
            shot("nav-\(name)-3-typed")
        }
        save(name)
        XCTAssertTrue(back, "\(name): Up from row \(n) (after \(k) right) climbs back to the search field; at \(where_())")
    }
    func testSearchUpFromChannels() { upFromResults(row: 0, right: 0, "up-channels") }
    func testSearchUpFromFilms() { upFromResults(row: 1, right: 0, "up-films") }
    func testSearchUpFromSeries() { upFromResults(row: 2, right: 0, "up-series") }
    func testSearchUpFromFilmsScrolled() { upFromResults(row: 1, right: 8, "up-films-scrolled") }
    func testSearchUpFromChannelsScrolled() { upFromResults(row: 0, right: 8, "up-channels-scrolled") }

    /// Any screen: go Down d times and Right k times into the content, then repeated Up reaches the tab bar,
    /// and Menu from the content goes one level up (the tab bar).
    func upToMenu(_ tab: String, down d: Int, right k: Int, extra: [String] = [], _ name: String) {
        launch(["-NXTab", tab] + extra)
        press(.down, d, wait: 1)
        if k > 0 { press(.right, k, wait: 1) }
        let start = where_()
        shot("nav-\(name)-1-start")
        var ok = false
        for _ in 0..<14 { press(.up, wait: 0.6); if onMenu { ok = true; break } }
        shot("nav-\(name)-2-up")
        XCTAssertTrue(ok, "\(name): repeated Up from \(start) reaches the tab bar; at \(where_())")
        // Menu from the content: one level up
        press(.down, d, wait: 1)
        let inContent = where_()
        press(.menu, wait: 1.5)
        shot("nav-\(name)-3-menu")
        XCTAssertTrue(onMenu, "\(name): Menu from \(inContent) goes to the tab bar; at \(where_())")
        save(name)
    }
    func testHomeDeepRowUp() { upToMenu("home", down: 5, right: 4, "home-deep") }
    func testLiveGuideUp() { upToMenu("live", down: 4, right: 1, "live-guide") }
    func testLiveGuidePreviewUp() { upToMenu("live", down: 3, right: 2, "live-preview") }
    func testFilmsGridUp() { upToMenu("films", down: 4, right: 3, "films-grid") }
    func testSeriesGridUp() { upToMenu("series", down: 4, right: 3, "series-grid") }
    func testSettingsPaneUp() { upToMenu("settings", down: 3, right: 1, "settings-pane") }
    func testSearchResultsUpToMenu() { upToMenu("search", down: 4, right: 3, extra: ["-NXSearch", "rtl"], "search-deep") }

    /// Detail page: Menu goes back to where it was opened, Up from the episodes reaches the buttons.
    func testDetailBack() {
        launch(["-NXTab", "home", "-NXOpen", "series:45370:House Of Guinness"])
        press(.down, 3, wait: 1)
        let start = where_()
        var ok = false
        for _ in 0..<8 { press(.up, wait: 0.6); if app.buttons.matching(NSPredicate(format: "hasFocus == true AND (label CONTAINS 'Play' OR label CONTAINS 'Resume' OR label CONTAINS 'Watch')")).count > 0 { ok = true; break } }
        shot("nav-detail-1-up")
        XCTAssertTrue(ok, "detail: Up from \(start) reaches the Play button; at \(where_())")
        press(.menu, wait: 2)
        shot("nav-detail-2-menu")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "hasFocus == true AND label == 'Watch'")).count > 0 || onMenu, "detail: Menu goes back to Home; at \(where_())")
        save("detail")
    }

    /// Home hero: Up from Watch or My List reaches the tab bar; Right/Left move between the two buttons.
    func testHomeHeroUp() {
        launch(["-NXTab", "home"])
        press(.down, wait: 1)                                  // menu -> hero
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "hasFocus == true AND label == 'Watch'")).count > 0, "hero Watch first; at \(where_())")
        press(.up, wait: 1)
        XCTAssertTrue(onMenu, "Up from Watch reaches the tab bar; at \(where_())")
        press(.down, wait: 1); press(.right, wait: 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "hasFocus == true AND label CONTAINS 'My List'")).count > 0, "Right from Watch reaches My List; at \(where_())")
        press(.up, wait: 1)
        XCTAssertTrue(onMenu, "Up from My List reaches the tab bar; at \(where_())")
        save("hero")
    }

    /// After a search, other tabs never send focus to the (hidden) search keyboard.
    func testHiddenSearchKeyboardNotReachable() {
        launch(["-NXTab", "search", "-NXSearch", "rtl"])
        press(.down, wait: 1.5)
        app.typeText("x"); idle(2)
        for _ in 0..<4 { press(.up, wait: 0.6); if onMenu { break } }
        for _ in 0..<6 { press(.left, wait: 1.2) }            // to Home through every tab
        var bad: [String] = []
        for k in [XCUIRemote.Button.down, .up, .down, .down, .up, .up, .up, .down] {
            press(k, wait: 0.8)
            if focused.elementType == .keyboard { bad.append(where_()) }
        }
        shot("nav-hidden-search")
        save("hidden-search")
        XCTAssertTrue(bad.isEmpty, "Home never focuses the hidden search keyboard: \(bad)")
    }
}
