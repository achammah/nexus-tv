import XCTest

/// TestFlight report: "I cannot move down onto the search text field". From a cold launch on Home, the owner
/// walks the menu to Search with Left/Right and presses Down: focus must reach the search field (keyboard row).
final class SearchFocusTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    var focusedLabel: String { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label }
    /// The search field has focus: typing goes into it (the tvOS keyboard row is up).
    var searchFocused: Bool {
        app.searchFields.matching(NSPredicate(format: "hasFocus == true")).count > 0 || app.keyboards.count > 0
            || app.textFields.matching(NSPredicate(format: "hasFocus == true")).count > 0
    }
    /// From anywhere: up to the menu, then right until the Search tab has focus.
    func walkToSearch() {
        for _ in 0..<6 { if app.buttons.matching(NSPredicate(format: "label == 'Home' AND hasFocus == true")).count > 0 { break }; press(.up, wait: 0.5) }
        for _ in 0..<7 { if focusedLabel.contains("Search") { break }; press(.right, wait: 0.6) }
        XCTAssertTrue(focusedLabel.contains("Search"), "Search tab focused in the menu; focused: \(focusedLabel)")
    }
    func downToField(_ step: String) {
        var ok = false
        for _ in 0..<3 { press(.down, wait: 1.5); if searchFocused { ok = true; break } }
        shot("sf-" + step)
        XCTAssertTrue(ok, "\(step): Down from the Search tab reaches the search field; focused: \(focusedLabel)")
    }

    func run(_ extra: [String], _ name: String) {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "home"] + extra
        app.launch(); idle(12)
        walkToSearch()
        downToField(name + "-1-first")
        app.typeText("friends"); idle(3)
        XCTAssertTrue(app.searchFields.firstMatch.exists || app.staticTexts["friends"].exists || (app.searchFields.firstMatch.value as? String ?? "").contains("friends"), "typed into the field")
        // after a search: back to the menu, away and back to Search, Down again
        press(.menu, wait: 1)
        walkToSearch()
        press(.left, wait: 1); press(.right, wait: 1)
        downToField(name + "-2-after-search")
    }

    func testDownFromMenuReachesSearchField() { run([], "warm") }

    /// A person's pace: the menu walked quickly, one Down straight after reaching Search, no second try.
    func testOneQuickDownFromMenuReachesSearchField() {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "home"]
        app.launch(); idle(12)
        for _ in 0..<6 { if app.buttons.matching(NSPredicate(format: "label == 'Home' AND hasFocus == true")).count > 0 { break }; r.press(.up); idle(0.4) }
        for _ in 0..<5 { r.press(.right); idle(0.25) }
        idle(0.3)
        XCTAssertTrue(focusedLabel.contains("Search"), "Search tab focused; focused: \(focusedLabel)")
        r.press(.down); idle(1.2)
        shot("sf-quick-1")
        XCTAssertTrue(searchFocused, "one Down from the Search tab reaches the search field; focused: \(focusedLabel)")
    }

    /// The tabs before Search were opened first (they stay alive behind it), then a result was opened and closed.
    func testDownReachesSearchFieldAfterOtherTabsAndADetail() {
        app = XCUIApplication()
        app.launchArguments = ["-NXTab", "home"]
        app.launch(); idle(12)
        for _ in 0..<6 { if app.buttons.matching(NSPredicate(format: "label == 'Home' AND hasFocus == true")).count > 0 { break }; press(.up, wait: 0.5) }
        for _ in 0..<4 { press(.right, wait: 2.5) }            // Live TV, Films, Series, My List open on the way
        walkToSearch()
        downToField("tabs-1-first")
        app.typeText("friends"); idle(4)
        for _ in 0..<4 { press(.down, wait: 1); if !app.keyboards.element.exists { break } }
        press(.select, wait: 4)                                // open a result
        shot("sf-tabs-2-result")
        press(.menu, wait: 2)                                  // back to search
        shot("sf-tabs-3-back")
        for _ in 0..<4 { press(.up, wait: 1); if searchFocused { break } }
        XCTAssertTrue(searchFocused, "back from a result, Up reaches the search field again; focused: \(focusedLabel)")
        walkToSearch()
        downToField("tabs-4-from-menu")
    }

    /// Same with no cached lists: the search index is being prepared (the black pill is on screen).
    func testDownFromMenuReachesSearchFieldWhileIndexPrepares() { run(["-NXClearCache", "YES"], "preparing") }
}
