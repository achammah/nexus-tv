import XCTest
@testable import NexusTVMac

/// The browse rules (shelves by family, clean names, small lists) on real provider list names, no provider call.
final class BrowseTests: XCTestCase {
    // provider names as the API sends them (language tag first), with their title counts
    private let films: [(String, Int)] = [
        ("|EN| TOP IMDB/OSCAR MOVIES", 161), ("|EN| 4K MOVIES", 1389), ("|EN| 4K CHILDREN", 175), ("NETFLIX KIDS", 145),
        ("NETFLIX MOVIES", 2489), ("|EN| DRAMA", 754), ("APPLE+ MOVIES", 38), ("APPLE+ KIDS", 11), ("|EN| DISNEY+", 152),
        ("|EN| ACTION/THRILLER", 1379), ("|EN| SCIENCE FICTION/FANTASTY", 386), ("|EN| PRE-RELEASES/SD CAM", 4),
        ("|EN| FRENCH MOVIES / ENG SUB", 961), ("|EN| CLASSIC MOVIES COLLECTION", 1648), ("|FR| DRAME", 400), ("|EN| ADULT", 99),
    ]
    private func lib(_ lang: String = "EN") -> Browse.Library {
        let cats = films.enumerated().map { XCategory(id: "\($0.offset)", name: $0.element.0) }
        let counts = Dictionary(uniqueKeysWithValues: films.enumerated().map { ("\($0.offset)", $0.element.1) })
        return Browse.library(cats, counts: counts, language: lang)
    }

    func testCleanNamesCarryNoLanguageTag() {
        XCTAssertEqual(Browse.label(Browse.raw("|EN| SCIENCE FICTION/FANTASTY")), "Sci-fi & fantasy")
        XCTAssertEqual(Browse.label(Browse.raw("|EN| ACTION/THRILLER")), "Action & thriller")
        XCTAssertEqual(Browse.label(Browse.raw("NETFLIX MOVIES")), "Netflix")
        XCTAssertEqual(Browse.label("DISNEY+ KIDS"), "Disney+ kids")
        for s in lib().shelves { for l in s.lists { XCTAssertFalse(l.label.hasSuffix("· EN") || l.label.contains("|"), l.label) } }
    }

    func testFamiliesInPageOrderAndServices() {
        let l = lib()
        XCTAssertEqual(l.shelves.first?.name, "Streaming services", "the services shelf comes first")
        XCTAssertEqual(l.services.map(\.service.name), ["Netflix", "Disney+", "Apple TV+"])
        XCTAssertEqual(l.services.first?.lists.map(\.label), ["Netflix", "Netflix kids"], "a service holds its own lists, biggest first")
        XCTAssertTrue(l.shelves.contains { $0.name == "4K & UHD" && $0.lists.map(\.label) == ["All 4K films", "4K children"] })
        XCTAssertTrue(l.shelves.contains { $0.name == "World & languages" })
        XCTAssertTrue(l.shelves.contains { $0.name == "Collections & eras" })
        XCTAssertEqual(l.shelves.first { $0.name == "Genres" }?.lists.first?.label, "Action & thriller", "biggest list first")
    }

    func testSmallListsAndCamCopiesHiddenAdultLeftOut() {
        let l = lib()
        XCTAssertEqual(Set(l.hidden.map(\.label)), ["Apple TV+ Kids", "Pre-releases (cam copies)"])
        XCTAssertFalse((l.shelves.flatMap(\.lists) + l.hidden).contains { $0.raw.contains("ADULT") })
    }

    func testPageLanguage() {
        XCTAssertFalse(lib("EN").shelves.flatMap(\.lists).contains { $0.label == "Drame" }, "French lists are not on the English page")
        XCTAssertTrue(lib("FR").shelves.flatMap(\.lists).contains { $0.label == "Drame" })
        XCTAssertTrue(lib("FR").services.contains { $0.service.name == "Netflix" }, "untagged lists show in both languages")
    }

    func testLiveMergesQualityCopiesAndPutsEventsLast() {
        let names = ["US| GENERAL", "US| GENERAL HEVC", "US| NBC", "US| ESPN PLUS", "US| SOCCER PPV", "US| NEWS NETWORK", "US| KIDS NETWORK", "US| TINY", "US| NBA"]
        let n = [120, 40, 201, 500, 200, 68, 50, 3, 30]
        let groups = names.enumerated().map { XCategory(id: "l\($0.offset)", name: $0.element) }
        let counts = Dictionary(uniqueKeysWithValues: n.enumerated().map { ("l\($0.offset)", $0.element) })
        let live = Browse.live(groups, counts: counts)
        let all = live.shelves.flatMap(\.lists)
        let general = all.first { $0.label == "General" }
        XCTAssertEqual(general?.ids, ["l0", "l1"], "General and General HEVC are one list")
        XCTAssertEqual(general?.count, 160)
        XCTAssertEqual(live.shelves.last?.name, "Events & pay-per-view")
        XCTAssertTrue(live.shelves.last?.lists.allSatisfy(\.muted) ?? false, "events are dimmed")
        XCTAssertEqual(live.hidden.map(\.label), ["Tiny"], "a list under 8 channels is hidden")
        XCTAssertTrue(live.shelves.contains { $0.name == "News & kids" }, "one-list families share a shelf; got \(live.shelves.map(\.name))")
        XCTAssertEqual(live.channels, 1212)
    }

    func testCounts() {
        XCTAssertEqual(Browse.count(1389, "film"), "1,389 films")
        XCTAssertEqual(Browse.count(1, "film"), "1 film")
        XCTAssertEqual(Browse.count(247, "series"), "247 series")
        XCTAssertEqual(Browse.count(1, "list"), "1 list")
    }

    /// Netflix has an untagged "NETFLIX MOVIES" and an English "NETFLIX": inside Netflix they must not both read "All".
    func testServiceListNamesAreDistinct() {
        let cats = [XCategory(id: "a", name: "NETFLIX MOVIES"), XCategory(id: "b", name: "|EN| NETFLIX"), XCategory(id: "c", name: "NETFLIX KIDS")]
        let lib = Browse.library(cats, counts: ["a": 2489, "b": 305, "c": 145], language: "EN")
        let nf = lib.services.first { $0.service.name == "Netflix" }!
        XCTAssertEqual(Browse.serviceLabels(nf.lists, "Netflix"), ["All", "All in English", "Kids"])
    }
}
