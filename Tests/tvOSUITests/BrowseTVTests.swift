import XCTest

/// Films, Series and Live TV as shelves by family (2a) with banner cards (3b), driven with the remote.
/// Each journey fails on the old screens (one flat category list with " · EN" names, the three-column guide).
final class BrowseTVTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    var focused: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch }
    func launch(_ tab: String) { app = XCUIApplication(); app.launchArguments = ["-NXTab", tab]; app.launch(); idle(14) }
    func shelf(_ name: String) -> XCUIElement { app.descendants(matching: .any)["shelf:" + name] }
    /// Texts still carrying a language tag (the old list said "EN · Drama").
    func tagged() -> [String] {
        app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.hasSuffix("· EN") || $0.hasPrefix("EN · ") || $0.hasPrefix("FR · ") }
    }
    /// Down until a card has focus.
    @discardableResult func downToCard(max: Int = 6) -> Bool {
        for _ in 0..<max { if focused.identifier.hasPrefix("card:") { return true }; press(.down, wait: 1) }
        return focused.identifier.hasPrefix("card:")
    }

    func testFilmsShelvesThenServiceThenList() {
        launch("films")
        XCTAssertTrue(shelf("Streaming services").waitForExistence(timeout: 20), "Streaming services shelf")
        XCTAssertTrue(shelf("Genres").exists, "Genres shelf")
        XCTAssertEqual(tagged(), [], "no list name carries a language tag")
        XCTAssertTrue(downToCard(), "Down reaches the service cards; focused: \(focused.identifier)")
        let service = focused.identifier
        shot("browse-1-films")
        press(.select, wait: 3)
        shot("browse-2-service")
        XCTAssertTrue(downToCard(max: 3) || focused.identifier.hasPrefix("card:"), "the service's lists; focused: \(focused.identifier)")
        XCTAssertNotEqual(focused.identifier, service, "a list inside the service, not the service card")
        press(.select, wait: 8)
        shot("browse-3-list")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile:' OR identifier BEGINSWITH 'poster:'")).count > 0
                      || app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' films'")).count > 0, "the list's posters")
        press(.menu, wait: 2)
        shot("browse-4-back")
        XCTAssertTrue(focused.identifier.hasPrefix("card:"), "Menu returns to the service's lists; focused: \(focused.identifier) \(focused.label)")
        press(.menu, wait: 2)
        XCTAssertTrue(shelf("Streaming services").waitForExistence(timeout: 5), "Menu again returns to the shelves")
        XCTAssertEqual(focused.identifier, service, "focus is back on the service card it opened")
    }

    func testSeriesShelves() {
        launch("series")
        XCTAssertTrue(shelf("Streaming services").waitForExistence(timeout: 20), "Streaming services shelf")
        XCTAssertEqual(tagged(), [], "no list name carries a language tag")
        XCTAssertTrue(app.buttons["Français"].exists, "one page-level language choice")
    }

    func testLiveShelvesOpenTheGuideOnAList() {
        launch("live")
        // Live (design A): pinned countries first; a pinned country opens its shelves by family
        for _ in 0..<6 { if focused.identifier.hasPrefix("live:pinned:") { break }; press(.down, wait: 1) }
        XCTAssertTrue(focused.identifier.hasPrefix("live:pinned:"), "a pinned country; focused: \(focused.identifier)")
        press(.select, wait: 6)
        XCTAssertTrue(shelf("Main channels").waitForExistence(timeout: 30), "Main channels shelf")
        let names = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'shelf:'")).allElementsBoundByIndex.map(\.identifier)
        if names.contains("shelf:Events & pay-per-view") { XCTAssertEqual(names.last, "shelf:Events & pay-per-view", "events last") }
        XCTAssertTrue(downToCard(), "Down reaches a list card")
        press(.select, wait: 6)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Click to watch'")).firstMatch.waitForExistence(timeout: 10), "the guide on that list")
        press(.menu, wait: 2)
        XCTAssertTrue(shelf("Main channels").waitForExistence(timeout: 5), "Menu returns to the shelves")
        XCTAssertTrue(focused.identifier.hasPrefix("card:"), "focus is back on a list card; focused: \(focused.identifier) \(focused.label)")
    }
}
