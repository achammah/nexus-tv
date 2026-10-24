import XCTest

/// The opening (native vector animation) plays at launch over Home: it is on screen at once, a press skips it,
/// and without a press it gives way to Home by itself (Home fades in from 1.8 s, the opening is gone after 3 s).
final class OpeningTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!

    func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-NXOpening", "YES", "-NXTab", "home"]
        app.launch()
    }
    var opening: XCUIElement { app.descendants(matching: .any)["opening"] }
    var menuHome: XCUIElement { app.buttons["Home"] }

    func testOpeningPlaysThenHome() {
        launch()
        XCTAssertTrue(opening.waitForExistence(timeout: 3), "the opening is on screen at launch")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: opening)
        wait(for: [gone], timeout: 6)
        XCTAssertTrue(menuHome.waitForExistence(timeout: 5), "Home's menu after the opening")
        r.press(.up); idle(1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "hasFocus == true")).count > 0, "the remote moves focus on Home")
    }

    func testPressSkipsOpening() {
        launch()
        XCTAssertTrue(opening.waitForExistence(timeout: 3), "the opening is on screen at launch")
        let t0 = Date()
        r.press(.select)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: opening)
        wait(for: [gone], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5, "a press ends the opening at once")
    }
}
