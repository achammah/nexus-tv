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
    var focusedId: String { app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.identifier }
    func type(_ text: String) {
        press(.select, wait: 2); app.typeText(text); idle(1); press(.menu, wait: 2)
    }
    /// Onboarding v2: Server, Username, Password (Xtream login), then the Sign in button.
    func fill(_ server: String, _ user: String, _ pass: String) {
        for _ in 0..<6 { if focusedId == "onboarding-field-0" { break }; press(.down, wait: 0.6) }
        XCTAssertEqual(focusedId, "onboarding-field-0", "the Server row has focus")
        type(server); press(.down, wait: 1)
        type(user); press(.down, wait: 1)
        type(pass); press(.down, wait: 1)
        for _ in 0..<3 { if focusedId == "onboarding-go" { break }; press(.down, wait: 0.6) }
        XCTAssertEqual(focusedId, "onboarding-go", "Sign in focused")
    }
    var onboarding: XCUIElement { app.descendants(matching: .any)["onboarding"] }

    func testFirstLaunchAddsAccount() {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["NX_SERVER"], let user = env["NX_USER"], let pass = env["NX_PASS"] else { XCTFail("NX_* not set"); return }
        app = XCUIApplication()
        app.launchArguments = ["-NXResetAccounts", "YES", "-NXResetUser", "YES", "-NXTab", "home"]
        app.launch(); idle(8)
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10), "first launch shows the onboarding")
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-skip"].exists, "Skip for now")
        shot("o1-first-launch")
        // a wrong login: refused, still on the screen
        fill(server, "nexus-wrong-user", "wrong-password")
        press(.select, wait: 10)
        privateShot("o2-refused")
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-message"].exists, "a wrong login is refused with a message")
        XCTAssertTrue(onboarding.exists, "still asking")
        // the real login: Home, search built in the background
        app.terminate()
        app.launchArguments = ["-NXTab", "home"]
        app.launch(); idle(8)
        fill(server, user, pass)
        let signIn = Date()
        press(.select, wait: 0)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: onboarding)
        if XCTWaiter().wait(for: [gone], timeout: 40) != .completed {
            privateShot("o3-still-asking")             // the form shows the typed server: kept out of shots/
            XCTFail("still on the onboarding after a valid login")
            return
        }
        XCTAssertTrue(app.staticTexts["Belgium"].waitForExistence(timeout: 60), "Home with live rows after sign-in")
        print(String(format: "NXTIME Home rows %.1f s after sign-in", Date().timeIntervalSince(signIn)))
        shot("o3-home")
    }
}
