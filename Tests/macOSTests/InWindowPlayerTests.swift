import XCTest
@testable import NexusTVMac

/// The player plays inside the library window: no second window; leaving it returns to the page it came from.
@MainActor
final class InWindowPlayerTests: XCTestCase {
    func testPlayFromFilmPageStaysInTheWindowAndReturnsToIt() {
        let nav = MacNav()
        nav.go(.films)
        let film = MediaItem(kind: .film, id: "1773307", name: "The Sand Castle", ext: "mkv")
        nav.open(film)
        Player(nav: nav).play(film)
        XCTAssertEqual(nav.playing?.item, film, "the film plays in the library window")
        XCTAssertEqual(nav.detail, film, "its page stays underneath")
        nav.closePlayer()                      // Esc or the back chevron
        XCTAssertNil(nav.playing)
        XCTAssertEqual(nav.detail, film, "back on the film page")
        XCTAssertEqual(nav.page, .films)
    }
    func testNoSeparatePlayerWindowScene() throws {
        // the app declares one window: the library (the player window scene was removed)
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/macOSTests/InWindowPlayerTests.swift", with: "macOS/NexusTVMacApp.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("WindowGroup(\"Player\""), "no separate player window")
    }
}
