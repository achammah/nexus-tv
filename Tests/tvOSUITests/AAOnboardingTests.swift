import XCTest

/// First launch with no account (runs first: the class name sorts first). The app starts like a new install
/// (-NXResetAccounts YES), refuses a wrong login, accepts the real one, shows Home, and builds search in the background.
final class AAOnboardingTests: XCTestCase {
    let r = XCUIRemote.shared
    var app: XCUIApplication!
    var dir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) }
    /// Captures that show typed login values stay out of shots/.
    func privateShot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/../../build/private-" + n + ".png")) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: Double = 1) { for _ in 0..<n { r.press(b); idle(0.5) }; idle(wait) }
    func type(_ text: String) {
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "hasFocus == true")).count + app.secureTextFields.matching(NSPredicate(format: "hasFocus == true")).count > 0, "a text field has focus")
        press(.select, wait: 2); app.typeText(text); idle(1); press(.menu, wait: 2)
    }
    func fill(_ name: String, _ server: String, _ user: String, _ pass: String) {
        type(name); press(.down, wait: 1)
        type(server); press(.down, wait: 1)
        type(user); press(.down, wait: 1)
        type(pass); press(.down, wait: 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Check and sign in' AND hasFocus == true")).count > 0, "sign-in button focused")
    }

    func testFirstLaunchAddsAccount() {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["NX_SERVER"], let user = env["NX_USER"], let pass = env["NX_PASS"] else { XCTFail("NX_* not set"); return }
        app = XCUIApplication()
        app.launchArguments = ["-NXResetAccounts", "YES", "-NXResetUser", "YES", "-NXTab", "home"]
        app.launch(); idle(6)
        XCTAssertTrue(app.staticTexts["Add your IPTV account"].exists, "first launch asks for an account")
        XCTAssertFalse(app.buttons["Cancel"].exists, "no way around it on first launch")
        shot("o1-first-launch")
        // a wrong login: refused, still on the screen
        fill("Wrong", server, "nexus-wrong-user", "wrong-password")
        press(.select, wait: 8)
        privateShot("o2-refused")
        XCTAssertTrue(app.staticTexts["The provider refused this login."].exists, "a wrong login is refused")
        XCTAssertTrue(app.staticTexts["Add your IPTV account"].exists, "still asking")
        // the real login: Home, search built in the background
        app.terminate()
        app.launchArguments = ["-NXTab", "home"]
        app.launch(); idle(6)
        fill("My IPTV", server, user, pass)
        let signIn = Date()
        press(.select, wait: 0)
        // signed in when the account screen is gone (it covers Home while it is up)
        let ask = app.staticTexts["Add your IPTV account"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ask)
        if XCTWaiter().wait(for: [gone], timeout: 30) != .completed {
            privateShot("o3-still-asking")             // the form shows the typed server: kept out of shots/
            XCTFail("still on the account screen after a valid login: \(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The provider'")).firstMatch.label)")
            return
        }
        XCTAssertTrue(app.staticTexts["Belgium"].waitForExistence(timeout: 60), "Home with live rows after sign-in")
        print(String(format: "NXTIME Home rows %.1f s after sign-in", Date().timeIntervalSince(signIn)))
        let progress = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Preparing search'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30), "search index built in the background, with a progress line")
        shot("o3-home-preparing-search")
        // browsing does not wait for it
        press(.down, 2, wait: 2)
        shot("o4-browsing-while-preparing")
    }
}
