import Foundation
import SwiftUI

private func loadJSON<T: Decodable>(_ key: String, _ fallback: T) -> T {
    guard let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
    return v
}
private func saveJSON<T: Encodable>(_ key: String, _ v: T) {
    if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
}

// MARK: - My List, Favourites, Continue watching (kept per account)

struct Favourite: Codable, Hashable {
    var item: MediaItem     // a live channel
    var cc: String          // its country code ("BE"), so it shows first in that country's Home row
}

@MainActor
final class UserStore: ObservableObject {
    @Published private(set) var myList: [MediaItem] = []
    @Published private(set) var resume: [String: ResumePoint] = [:]
    @Published private(set) var favs: [Favourite] = []
    private var suffix = ""

    init() { load(account: AccountVault.activeId) }

    /// Each account keeps its own lists ("default" = the first account, stored without a suffix).
    func load(account id: String) {
        suffix = id == "default" ? "" : "@" + id
        // test hook: -NXResetUser YES starts with empty lists
        if UserDefaults.standard.bool(forKey: "NXResetUser") {
            for k in ["nx.mylist", "nx.resume", "nx.favs"] { UserDefaults.standard.removeObject(forKey: k + suffix) }
            UserDefaults.standard.removeObject(forKey: "nx.tracks"); trackPrefs = [:]   // remembered audio and subtitle choices
        }
        myList = loadJSON("nx.mylist" + suffix, [])
        resume = loadJSON("nx.resume" + suffix, [:])
        favs = loadJSON("nx.favs" + suffix, [])
    }
    private func save() {
        saveJSON("nx.mylist" + suffix, myList); saveJSON("nx.resume" + suffix, resume); saveJSON("nx.favs" + suffix, favs)
    }

    // My List
    func inList(_ it: MediaItem) -> Bool { myList.contains { $0.key == it.key } }
    func toggle(_ it: MediaItem) {
        if inList(it) { myList.removeAll { $0.key == it.key }; show("Removed from My List") }
        else { myList.insert(it, at: 0); show("Added to My List") }
        save()
    }

    // Favourite channels
    func isFav(_ id: String) -> Bool { favs.contains { $0.item.id == id } }
    func toggleFav(_ it: MediaItem, cc: String) {
        if isFav(it.id) { favs.removeAll { $0.item.id == it.id }; show("Removed from Favourites") }
        else { favs.insert(Favourite(item: it, cc: cc), at: 0); show("★  Added to Favourites") }
        save()
    }
    func favs(in cc: String) -> [MediaItem] { favs.filter { $0.cc == cc }.map(\.item) }
    /// Starred channels of countries that have no Home row ("More favourites").
    func favs(outside countries: [String]) -> [MediaItem] { favs.filter { !countries.contains($0.cc) }.map(\.item) }

    /// Continue watching: an entry exists from the moment playback starts; it goes only when the title
    /// is finished (last 60 s of a known duration). Position is saved every 15 s and on exit.
    func setResume(_ it: MediaItem, posMs: Int, durMs: Int) {
        if durMs > 0 && posMs > durMs - 60_000 { resume[it.key] = nil }
        else {
            // keep a picture we already had: a play started from a page without art must not blank the tile
            var item = it
            if item.img.isEmpty, let old = resume[it.key]?.item.img, !old.isEmpty { item.img = old }
            resume[it.key] = ResumePoint(item: item, posMs: max(0, posMs), durMs: max(0, durMs), at: Date())
        }
        save()
    }
    func finished(_ it: MediaItem) { resume[it.key] = nil; save() }
    func resumePoint(_ it: MediaItem) -> ResumePoint? { resume[it.key] }
    /// Newest first; one entry per series (its latest episode).
    var continueList: [ResumePoint] {
        var seen = Set<String>(), out: [ResumePoint] = []
        for r in resume.values.sorted(by: { $0.at > $1.at }) {
            let k = r.item.seriesId.map { "series:" + $0 } ?? r.item.key
            if seen.insert(k).inserted { out.append(r) }
            if out.count == 20 { break }
        }
        return out
    }
    func lastEpisode(ofSeries id: String) -> ResumePoint? {
        resume.values.filter { $0.item.kind == .episode && $0.item.seriesId == id }.max { $0.at < $1.at }
    }
    /// Removes an entry; for a series, every episode of it.
    func removeResume(_ r: ResumePoint) {
        if let sid = r.item.seriesId { resume = resume.filter { $0.value.item.seriesId != sid } } else { resume[r.item.key] = nil }
        save(); show("Removed from Continue watching")
    }

    // Subtitles: from names that say so, or learned when a file opens (an episode teaches its whole series)
    @Published private(set) var subs: [String: Bool] = loadJSON("nx.subs", [:])
    private static let subsName = try! NSRegularExpression(pattern: "\\bSUBS?\\b|ENG-SUB|VOST|SOUS-TITR|SUBTITLED", options: [.caseInsensitive])
    private func subsKey(_ it: MediaItem) -> String { it.seriesId.map { "series:" + $0 } ?? it.key }
    func hasSubs(_ it: MediaItem) -> Bool {
        if subs[subsKey(it)] == true { return true }
        for t in [it.name, it.sub] where !t.isEmpty {
            if Self.subsName.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { return true }
        }
        return false
    }
    func learnSubs(_ it: MediaItem, _ has: Bool) {
        let k = subsKey(it)
        guard subs[k] != has else { return }
        subs[k] = has; saveJSON("nx.subs", subs)
    }

    // Audio and subtitle choice, per film and per series (every episode): language first, track position as fallback
    private var trackPrefs: [String: TrackPref] = loadJSON("nx.tracks", [:])
    /// A title's own choice first; a title never set takes the last language picked anywhere (language only,
    /// since track positions differ from file to file).
    func trackPref(_ it: MediaItem) -> TrackPref? {
        let own = trackPrefs[subsKey(it)], last = trackPrefs["*"]
        guard let last else { return own }
        var p = own ?? TrackPref()
        if p.audioLang == nil, p.audioPos == nil { p.audioLang = last.audioLang }
        if p.subLang == nil, p.subPos == nil, p.subOff == nil, p.subOnline == nil { p.subLang = last.subLang; p.subOff = last.subOff; p.subOnline = last.subOnline }
        return p
    }
    func setTrackPref(_ it: MediaItem, _ change: (inout TrackPref) -> Void) {
        var p = trackPrefs[subsKey(it)] ?? TrackPref()
        change(&p)
        trackPrefs[subsKey(it)] = p
        var g = trackPrefs["*"] ?? TrackPref()
        if let a = p.audioLang { g.audioLang = a }
        if p.subLang != nil || p.subOff != nil || p.subOnline != nil { g.subLang = p.subLang; g.subOff = p.subOff; g.subOnline = p.subOnline }
        trackPrefs["*"] = g
        saveJSON("nx.tracks", trackPrefs)
    }

    func clearMyList() { myList = []; save(); show("My List cleared") }
    func clearResume() { resume = [:]; save(); show("Continue watching cleared") }
    func clearFavs() { favs = []; save(); show("Favourites cleared") }

    func show(_ msg: String) { Toaster.shared.show(msg) }
}

struct TrackPref: Codable {
    var audioLang: String? = nil
    var audioPos: Int? = nil
    var subLang: String? = nil
    var subPos: Int? = nil
    var subOff: Bool? = nil
    var subOnline: String? = nil    // the owner picked OpenSubtitles in this language: the next episode fetches its best match
}

/// Short messages at the bottom of the screen. Kept apart from UserStore so a toast never redraws the tiles.
@MainActor
final class Toaster: ObservableObject {
    static let shared = Toaster()
    @Published private(set) var text: String? = nil
    private var task: Task<Void, Never>?
    func show(_ msg: String) {
        text = msg
        task?.cancel()
        task = Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if !Task.isCancelled { text = nil } }
    }
}

/// Screen chrome state that changes during focus moves (kept out of Nav, which every tile observes).
@MainActor
final class Chrome: ObservableObject {
    static let shared = Chrome()
    /// Home: header and menu hide while rows pass under them.
    @Published var headerHidden = false { didSet { if headerHidden { scrolled = true } } }
    /// Home is scrolled below its first row: a black band covers the rows under the header (also while the menu has focus).
    @Published var scrolled = false
}

// MARK: - Settings

enum TabID: String, Codable, CaseIterable, Identifiable {
    case home, live, films, series, mylist, search, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: "Home"; case .live: "Live"; case .films: "Films"; case .series: "Series"
        case .mylist: "My List"; case .search: "Search"; case .settings: "Settings"
        }
    }
    var icon: String? { self == .search ? "magnifyingglass" : (self == .settings ? "gearshape.fill" : nil) }
}

struct Toggled<ID: Codable & Hashable>: Codable, Hashable { var id: ID; var visible: Bool }

/// Home rows: fixed rows plus one live row per chosen country ("live:BE").
enum HomeRow {
    static let fixed = ["continue", "mylist", "favMore", "newFilms", "topSeries"]
    /// The rows the Mac Home draws (plus one "live:CC" row per pinned country).
    static let mac: Set<String> = ["continue", "mylist", "newFilms", "topSeries"]
    static func label(_ id: String) -> String {
        switch id {
        case "continue": return "Continue watching"
        case "mylist": return "My List"
        case "favMore": return "More favourites"
        case "newFilms": return "New films"
        case "topSeries": return "Top series"
        case let x where x.hasPrefix("list:"): return x
        default:
            if id.hasPrefix("live:") { return "Live · " + Countries.name(String(id.dropFirst(5))) }
            return id
        }
    }
}

/// A provider category shown as a Home row: t = live | film | series.
struct HomeList: Codable, Hashable {
    var t: ItemKind
    var id: String
    var name: String
    var key: String { "list:\(t.rawValue):\(id)" }
}

enum Countries {
    static let names: [String: String] = [
        "BE": "Belgium", "FR": "France", "UK": "UK", "US": "US", "NL": "Netherlands", "DE": "Germany", "ES": "Spain", "IT": "Italy",
        "PT": "Portugal", "CA": "Canada", "AR": "Arabic", "TR": "Turkey", "PL": "Poland", "CH": "Switzerland", "AT": "Austria",
        "AU": "Australia", "NZ": "New Zealand", "IE": "Ireland", "GR": "Greece", "BR": "Brazil", "LAT": "Latin America", "ASIA": "Asia",
        "AFR": "Africa", "EXYU": "Ex-Yugoslavia", "CZ": "Czechia", "RO": "Romania", "BG": "Bulgaria", "HU": "Hungary", "SK": "Slovakia",
        "SE": "Sweden", "IR": "Iran", "IS": "Israel", "AL": "Albania", "HR": "Croatia", "RS": "Serbia", "MK": "North Macedonia",
        "CY": "Cyprus", "FI": "Finland", "RU": "Russia", "UKR": "Ukraine", "IN": "India", "PK": "Pakistan", "BEE": "beIN / Arabic sports",
        "CRB": "Caribbean", "KU": "Kurdish", "ID": "Indonesia", "MY": "Malaysia", "SG": "Singapore", "EU": "Europe", "MT": "Malta",
        "LT": "Lithuania", "EST": "Estonia", "GE": "Georgia", "AM": "Armenia", "BY": "Belarus", "BAN": "Bangladesh", "SL": "Slovenia",
        "BH": "Bosnia", "CG": "Montenegro", "NA": "North Africa", "KO": "Kosovo", "LA": "Latin America", "KA": "Kazakhstan",
    ]
    static func name(_ cc: String) -> String { names[cc] ?? cc }
}

enum Languages {
    static let names: [String: String] = ["": "Untagged (Netflix, Disney+…)", "EN": "English", "FR": "French", "MULTI": "Multi-language",
                                          "NL": "Dutch", "DE": "German", "ES": "Spanish", "IT": "Italian", "AR": "Arabic", "PL": "Polish",
                                          "TR": "Turkish", "PT": "Portuguese", "IN": "Indian", "QC": "Québec"]
    static func name(_ t: String) -> String { names[t] ?? t }
    static func short(_ t: String) -> String { t.isEmpty ? "" : t }
}

@MainActor
final class Settings: ObservableObject {
    static let defaultTabs: [Toggled<TabID>] = [.home, .live, .films, .series, .mylist, .search].map { Toggled(id: $0, visible: true) }
    static let defaultCountries = ["BE", "FR", "UK", "US"]
    static let defaultLanguages = ["EN", "FR", "MULTI", ""]

    @Published var tabs: [Toggled<TabID>] { didSet { saveJSON("nx.tabs", tabs) } }
    @Published var homeRows: [Toggled<String>] { didSet { saveJSON("nx.homeRows.v2", homeRows) } }
    @Published var countries: [String] { didSet { saveJSON("nx.countries", countries); syncRows() } }
    @Published var languages: [String] { didSet { saveJSON("nx.languages", languages) } }
    /// Categories the owner added as Home rows (Settings › Lists).
    @Published var lists: [HomeList] { didSet { saveJSON("nx.lists", lists); syncRows() } }
    /// Tile order the owner set inside a Home row (row id -> item keys).
    @Published var tileOrder: [String: [String]] { didSet { saveJSON("nx.tileOrder", tileOrder) } }

    init() {
        // test hook: -NXResetLayout YES starts with the default menu and Home rows
        if UserDefaults.standard.bool(forKey: "NXResetLayout") {
            UserDefaults.standard.removeObject(forKey: "nx.tabs"); UserDefaults.standard.removeObject(forKey: "nx.homeRows.v2")
        }
        tabs = loadJSON("nx.tabs", Settings.defaultTabs)
        countries = loadJSON("nx.countries", Settings.defaultCountries)
        languages = loadJSON("nx.languages", Settings.defaultLanguages)
        lists = loadJSON("nx.lists", [])
        tileOrder = loadJSON("nx.tileOrder", [:])
        homeRows = loadJSON("nx.homeRows.v2", Settings.defaultRows(Settings.defaultCountries))
        syncRows()
    }

    /// Owner order: Continue watching, My List, Belgium, New films, France, Top series, UK, US.
    static func defaultRows(_ cc: [String]) -> [Toggled<String>] {
        var r: [Toggled<String>] = [Toggled(id: "continue", visible: true), Toggled(id: "mylist", visible: true)]
        let order = ["live:BE", "favMore", "newFilms", "live:FR", "topSeries", "live:UK", "live:US"]
        for id in order where !id.hasPrefix("live:") || cc.contains(String(id.dropFirst(5))) { r.append(Toggled(id: id, visible: true)) }
        for c in cc where !["BE", "FR", "UK", "US"].contains(c) { r.append(Toggled(id: "live:" + c, visible: true)) }
        return r
    }

    /// One live row per chosen country: new countries are added (hidden), removed ones go.
    private func syncRows() {
        var rows = homeRows.filter { !$0.id.hasPrefix("live:") || countries.contains(String($0.id.dropFirst(5))) }
        for f in HomeRow.fixed where !rows.contains(where: { $0.id == f }) {
            // "More favourites" (starred channels of countries without a row) goes before New films
            if f == "favMore", let i = rows.firstIndex(where: { $0.id == "newFilms" }) { rows.insert(Toggled(id: f, visible: true), at: i) }
            else { rows.append(Toggled(id: f, visible: true)) }
        }
        for c in countries where !rows.contains(where: { $0.id == "live:" + c }) { rows.append(Toggled(id: "live:" + c, visible: true)) }
        rows = rows.filter { r in !r.id.hasPrefix("list:") || lists.contains { $0.key == r.id } }
        if rows != homeRows { homeRows = rows }
    }

    var visibleTabs: [TabID] { tabs.filter(\.visible).map(\.id) + [.settings] }
    var visibleRows: [String] { homeRows.filter(\.visible).map(\.id) }

    func move<T>(_ list: inout [Toggled<T>], _ i: Int, by d: Int) {
        let j = i + d
        guard list.indices.contains(i), list.indices.contains(j) else { return }
        list.swapAt(i, j)
    }

    func addList(_ l: HomeList) {
        guard !lists.contains(where: { $0.key == l.key }) else { return }
        lists.append(l)
        var rows = homeRows.filter { $0.id != l.key }
        rows.insert(Toggled(id: l.key, visible: true), at: min(1, rows.count))   // right after Continue watching
        homeRows = rows
    }
    func removeList(_ key: String) { lists.removeAll { $0.key == key } }
    func showAllRows() { for i in homeRows.indices { homeRows[i].visible = true } }
    func hideRow(_ id: String) { if let i = homeRows.firstIndex(where: { $0.id == id }) { homeRows[i].visible = false } }
    /// Moves a Home row past its visible neighbour (d = -1 up, +1 down).
    func moveRow(_ id: String, by d: Int) {
        let vis = visibleRows
        guard let vi = vis.firstIndex(of: id), vis.indices.contains(vi + d),
              let a = homeRows.firstIndex(where: { $0.id == id }), let b = homeRows.firstIndex(where: { $0.id == vis[vi + d] }) else { return }
        homeRows.swapAt(a, b)
    }

    /// Items of a row in the owner's order: known keys first in their saved order, new ones after in their own order.
    func ordered<T>(_ row: String, _ items: [T], key: (T) -> String) -> [T] {
        guard let order = tileOrder[row], !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated().sorted { a, b in
            let ra = rank[key(a.element)] ?? Int.max, rb = rank[key(b.element)] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
    /// Slides one tile left (-1) or right (+1) in its row; `keys` = the row's keys as shown.
    func moveTile(_ row: String, _ key: String, by d: Int, keys: [String]) {
        var k = keys
        guard let i = k.firstIndex(of: key), k.indices.contains(i + d) else { return }
        k.swapAt(i, i + d)
        tileOrder[row] = k
    }

    func resetLayout() {
        tabs = Settings.defaultTabs
        homeRows = Settings.defaultRows(countries)
        tileOrder = [:]
    }
}
