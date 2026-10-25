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
            for k in ["nx.credits", "nx.watched", "nx.lastKey"] { UserDefaults.standard.removeObject(forKey: k) }
            creditsSamples = [:]; watchedKeys = []; watching = StillWatching()
        }
        myList = loadJSON("nx.mylist" + suffix, [])
        resume = loadJSON("nx.resume" + suffix, [:])
        favs = loadJSON("nx.favs" + suffix, [])
        // test hook (Apple TV, simulator): -NXDemoSeries YES shows a made-up series in My List and Continue watching
        if UserDefaults.standard.bool(forKey: "NXDemoSeries") {
            let s = MediaItem(kind: .series, id: "demo", name: "House Of Guinness")
            let e = MediaItem(kind: .episode, id: "demo3", name: "House Of Guinness · S1 E3", ext: "mkv", sub: "Black Velvet", seriesId: "demo", seriesName: "House Of Guinness")
            myList = [s]
            resume = [e.key: ResumePoint(item: e, posMs: 634_000, durMs: 3_171_000, at: Date())]
            watchedKeys.formUnion(["episode:demo1", "episode:demo2"])
        }
    }
    private func save() {
        saveJSON("nx.mylist" + suffix, myList); saveJSON("nx.resume" + suffix, resume); saveJSON("nx.favs" + suffix, favs)
    }

    // My List
    func inList(_ it: MediaItem) -> Bool { myList.contains { $0.key == it.key } }
    func toggle(_ it: MediaItem) {
        if inList(it) { myList.removeAll { $0.key == it.key }; show("Removed from My List") }
        else { myList.insert(it, at: 0); show("Added to My List"); if it.kind == .series { FollowedShows.shared.noteFollowed(it) } }
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
        if durMs > 0 && posMs > durMs - 60_000 { resume[it.key] = nil; markWatched(it) }
        else {
            // keep a picture we already had: a play started from a page without art must not blank the tile
            var item = it
            if item.img.isEmpty, let old = resume[it.key]?.item.img, !old.isEmpty { item.img = old }
            resume[it.key] = ResumePoint(item: item, posMs: max(0, posMs), durMs: max(0, durMs), at: Date())
        }
        save()
        // an episode of a show plays: everything known of the show counts as seen (the "New episodes" row clears)
        if it.kind == .episode, let sid = it.seriesId {
            FollowedShows.shared.played(MediaItem(kind: .series, id: sid, name: it.seriesName ?? "", img: it.img))
        }
    }
    func finished(_ it: MediaItem) { resume[it.key] = nil; markWatched(it); save() }
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
    /// Followed shows: every series in My List plus every series with a Continue watching entry, most recently used first, at most 30.
    var followedSeries: [MediaItem] { EpisodeDiff.followed(myList: myList, resume: Array(resume.values)) }
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

    // MARK: player redesign 2026-10-25 (the Mac player uses the same members)

    /// Per show: where its credits start, as seconds BEFORE the end of the file; the last 5 samples (UserDefaults "nx.credits").
    private var creditsSamples: [String: [Int]] = loadJSON("nx.credits", [:])
    func creditsMemory(seriesId: String) -> [Int] { creditsSamples[seriesId] ?? [] }
    func recordCredits(seriesId: String, secondsBeforeEnd: Int) {
        guard secondsBeforeEnd > 0 else { return }
        creditsSamples[seriesId] = Array(((creditsSamples[seriesId] ?? []) + [secondsBeforeEnd]).suffix(CreditsCue.keep))
        saveJSON("nx.credits", creditsSamples)
    }

    /// Episodes the owner has watched to the end (shown as WATCHED on the episode cards); "nx.watched".
    private var watchedKeys: Set<String> = Set(loadJSON("nx.watched", [String]()))
    func isWatched(_ it: MediaItem) -> Bool { watchedKeys.contains(it.key) }
    func markWatched(_ it: MediaItem) { if watchedKeys.insert(it.key).inserted { saveJSON("nx.watched", Array(watchedKeys)) } }

    /// The "Still watching?" policy: key presses, autoplayed episodes, quick answers. Not published: nothing redraws on it.
    var watching = StillWatching(lastKeyAt: Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "nx.lastKey")))
    private var lastKeySaved = Date.distantPast
    /// Any remote key press (or, on Mac, a key press in the player window). The 90-minute rule survives a restart.
    func noteKey(_ now: Date = Date()) {
        watching.key(now)
        if now.timeIntervalSince(lastKeySaved) > 30 { lastKeySaved = now; UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "nx.lastKey") }
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
    static let fixed = ["updates", "continue", "mylist", "favMore", "newFilms", "topSeries"]
    /// The rows the Mac Home draws (plus one "live:CC" row per pinned country).
    static let mac: Set<String> = ["updates", "continue", "mylist", "newFilms", "topSeries"]
    static func label(_ id: String) -> String {
        switch id {
        case "updates": return "New episodes"
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

    /// Owner order: New episodes, Continue watching, My List, Belgium, New films, France, Top series, UK, US.
    static func defaultRows(_ cc: [String]) -> [Toggled<String>] {
        var r: [Toggled<String>] = [Toggled(id: "updates", visible: true), Toggled(id: "continue", visible: true), Toggled(id: "mylist", visible: true)]
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
            // "New episodes" goes first, above Continue watching
            if f == "updates" { rows.insert(Toggled(id: f, visible: true), at: 0) }
            else if f == "favMore", let i = rows.firstIndex(where: { $0.id == "newFilms" }) { rows.insert(Toggled(id: f, visible: true), at: i) }
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


// MARK: - Credits cue and "Still watching?" (pure rules, unit tested; both apps)

/// Where the credits of an episode start, in order of trust:
/// 1. the show's memory: the median of the last 5 samples (seconds before the end) the owner gave by pressing Next episode
///    or by watching to the end;
/// 2. no memory: the file's subtitle cues go quiet for 45 s inside the last 6 minutes;
/// 3. otherwise the last 2 % of the runtime, never under 20 s.
enum CreditsCue {
    static let keep = 5                    // samples kept per show
    static let quietMs = 45_000            // no subtitle cue for this long ...
    static let quietWindowMs = 360_000     // ... inside the last 6 minutes
    static let sampleWindowMs = 480_000    // a press counts as a sample only with under 8 minutes left
    static let floorMs = 20_000

    /// Median of the last `keep` samples; nil when there are none. An even count averages the two middle values.
    static func median(_ samples: [Int]) -> Int? {
        let s = samples.suffix(keep).sorted()
        guard !s.isEmpty else { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Where the speech stopped: with `cueStartsMs` (start times of the subtitle cues), the start of a gap of 45 s that lies
    /// inside the last 6 minutes and is already over at `nowMs`. nil while the dialogue goes on.
    static func quietStart(cueStartsMs: [Int], nowMs: Int, lengthMs: Int) -> Int? {
        let windowStart = max(0, lengthMs - quietWindowMs)
        let last = cueStartsMs.filter { $0 <= nowMs }.max() ?? 0
        let from = max(windowStart, last)
        return nowMs - from >= quietMs ? from : nil
    }

    /// The credits cue in ms from the start of the file. Always a value: the 2 % rule is the floor.
    /// `cueStartsMs`: nil when the file has no subtitle track the player could read.
    static func cueMs(lengthMs: Int, memorySecondsBeforeEnd: [Int], cueStartsMs: [Int]?, nowMs: Int) -> Int {
        if let m = median(memorySecondsBeforeEnd) { return max(0, lengthMs - m * 1000) }
        if let c = cueStartsMs, !c.isEmpty, let q = quietStart(cueStartsMs: c, nowMs: nowMs, lengthMs: lengthMs) { return q }
        return lengthMs - max(lengthMs / 50, floorMs)
    }

    /// Sample from a press of Next episode / the end card's OK: seconds before the end, only with under 8 minutes left.
    static func pressSample(remainingMs: Int) -> Int? {
        remainingMs > 0 && remainingMs <= sampleWindowMs ? remainingMs / 1000 : nil
    }

    /// Sample when the file plays to its end: where the owner last interacted (seek or key) if that is inside the last 8
    /// minutes, else the quiet point; nil when neither is known.
    static func endSample(lengthMs: Int, lastInteractionMs: Int?, quietPointMs: Int?) -> Int? {
        if let i = lastInteractionMs, lengthMs - i > 0, lengthMs - i <= sampleWindowMs { return (lengthMs - i) / 1000 }
        if let q = quietPointMs, lengthMs - q > 0 { return (lengthMs - q) / 1000 }
        return nil
    }
}

/// When to ask "Still watching?" (asked at the start of an episode that autoplayed).
struct StillWatching: Equatable {
    var lastKeyAt: Date = .distantPast
    /// Mac: the last time the pointer moved while the player window was key.
    var lastPointerAt: Date = .distantPast
    /// Autoplayed episodes since the last key press of this session.
    var autoplays = 0
    /// "Keep watching" answers given within 10 s, in a row.
    var quickKeeps = 0
    /// 90 minutes; the simulator tests shorten it with -NXStillWindowSec.
    static var window: TimeInterval { let v = UserDefaults.standard.double(forKey: "NXStillWindowSec"); return v > 0 ? v : 90 * 60 }
    static let quickAnswer: TimeInterval = 10

    /// 2 autoplayed episodes; after two quick "Keep watching" answers in a row, 4.
    var threshold: Int { quickKeeps >= 2 ? 4 : 2 }
    mutating func key(_ now: Date) { lastKeyAt = now; autoplays = 0 }
    mutating func pointer(_ now: Date) { lastPointerAt = now }
    mutating func autoplayed() { autoplays += 1 }
    /// `windowIsKey`: Mac only (the player window is the key window).
    func shouldAsk(now: Date, windowIsKey: Bool = false) -> Bool {
        guard autoplays >= threshold else { return false }
        if now.timeIntervalSince(lastKeyAt) <= Self.window { return false }
        if windowIsKey && now.timeIntervalSince(lastPointerAt) <= Self.window { return false }
        return true
    }
    /// The owner answered the toast. "Keep watching" is a key press; a quick one counts towards the longer wait.
    mutating func answered(keep: Bool, after seconds: TimeInterval, now: Date) {
        if keep { quickKeeps = seconds <= Self.quickAnswer ? quickKeeps + 1 : 0; key(now) } else { quickKeeps = 0 }
    }
}


// MARK: - New episodes (both apps)

/// One episode of a show as the provider lists it.
struct EpisodeRef: Codable, Hashable, Sendable {
    var id: String
    var season: Int
    var num: Int
    var title: String
    var ext: String = ""
    var label: String { "S\(season) E\(num)" }
}

/// What the app has seen of one show: the episode ids and when it was recorded.
struct SeenRecord: Codable, Equatable {
    var ids: [String]
    var at: Date
}

/// A followed show with episodes the owner has not seen: one tile on the "New episodes" row, one slot in the hero.
struct NewShow: Codable, Hashable, Identifiable {
    var series: MediaItem               // kind .series, with its poster
    var episodes: [EpisodeRef]          // the new ones, newest first
    var backdrop = ""
    var plot = ""
    var facts: [String] = []
    var id: String { series.id }
    var newest: EpisodeRef { episodes[0] }
    var count: Int { episodes.count }
    /// "2 new"
    var badge: String { "\(count) new" }
    /// "S2 E5 · Title"
    var caption: String { newest.label + (newest.title.isEmpty ? "" : " · " + newest.title) }
    var kicker: String { "NEW EPISODE · S\(newest.season) E\(newest.num)" }
}

/// The pure rules of "New episodes": which episodes are new, which shows are followed, what the hero shows. Unit tested.
enum EpisodeDiff {
    static let cap = 30
    static let width = 3
    static let maxAge: TimeInterval = 3600

    /// Every episode of a show, seasons in order.
    static func refs(_ d: Details) -> [EpisodeRef] {
        d.seasons.flatMap { s in (d.episodes[s] ?? []).map { EpisodeRef(id: $0.id, season: Int(s) ?? 0, num: $0.num, title: $0.title, ext: $0.ext) } }
    }

    /// Newest first: the later season, then the later episode number.
    static func newestFirst(_ a: EpisodeRef, _ b: EpisodeRef) -> Bool { a.season != b.season ? a.season > b.season : a.num > b.num }

    /// The episodes whose id is not in the seen set, newest first. No seen set (the show was never recorded) = nothing is new.
    static func newEpisodes(current: [EpisodeRef], seen: Set<String>?) -> [EpisodeRef] {
        guard let seen else { return [] }
        return current.filter { !seen.contains($0.id) }.sorted(by: newestFirst)
    }

    /// The provider gave every episode a new id (none of the seen ones is left): that is a re-index, not new episodes.
    static func reindexed(current: [EpisodeRef], seen: Set<String>) -> Bool {
        !seen.isEmpty && current.count > 0 && !current.contains { seen.contains($0.id) }
    }

    /// The seen ids plus these episodes, in a stable order.
    static func merged(_ seen: [String], with eps: [EpisodeRef]) -> [String] {
        var out = seen, have = Set(seen)
        for e in eps where have.insert(e.id).inserted { out.append(e.id) }
        return out
    }

    /// Followed shows = every series in My List plus every series with a Continue watching entry. Most recently used first
    /// (Continue watching by time, then My List in its order), one entry per show, at most `cap`.
    static func followed(myList: [MediaItem], resume: [ResumePoint], cap: Int = EpisodeDiff.cap) -> [MediaItem] {
        var out: [MediaItem] = [], seen = Set<String>()
        func add(_ it: MediaItem) { if seen.insert(it.id).inserted { out.append(it) } }
        let listed = Dictionary(myList.filter { $0.kind == .series }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in resume.sorted(by: { $0.at > $1.at }) {
            guard r.item.kind == .episode, let sid = r.item.seriesId else { continue }
            add(listed[sid] ?? MediaItem(kind: .series, id: sid, name: r.item.seriesName ?? "", img: r.item.img))
        }
        for it in myList where it.kind == .series { add(it) }
        return Array(out.prefix(cap))
    }

    /// The episode to play and the ones after it (the same naming the show pages use).
    static func plan(episodes: [EpisodeRef], play id: String, series: MediaItem, title: String, poster: String) -> (item: MediaItem, next: [MediaItem])? {
        let all = episodes.sorted { $0.season != $1.season ? $0.season < $1.season : $0.num < $1.num }
        func make(_ e: EpisodeRef) -> MediaItem {
            MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(e.season) E\(e.num)", img: poster, ext: e.ext, sub: e.title, seriesId: series.id, seriesName: title)
        }
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        return (make(all[i]), all.dropFirst(i + 1).map(make))
    }
}

/// One hero slot: a followed show with new episodes (`update`), or a top series.
struct HomeHero: Hashable {
    var id: String
    var title: String
    var facts: [String]
    var plot: String
    var backdrop: String
    var cover: String
    var update: NewShow? = nil
    /// "NEW EPISODE · S2 E5", or "Top series"
    var kicker: String { update?.kicker ?? "Top series" }

    /// Shows with new episodes first (up to 5), then the top series that are not among them.
    static func list(updates: [NewShow], base: [HeroItem]) -> [HomeHero] {
        let up = updates.prefix(5).map { n in
            HomeHero(id: n.id, title: Clean.display(n.series.name), facts: n.facts, plot: n.plot, backdrop: n.backdrop, cover: n.series.img, update: n)
        }
        let ids = Set(up.map(\.id))
        let rest = base.filter { !ids.contains($0.id) }.map { h in
            HomeHero(id: h.id, title: h.title, facts: [h.year, h.genre, h.rating.isEmpty ? "" : "★ " + String(h.rating.prefix(3))].filter { !$0.isEmpty },
                     plot: h.plot, backdrop: h.backdrop, cover: h.cover)
        }
        return up + rest
    }
}

/// The new-episode memory of the followed shows (kept per account): what was seen, and the result of the last refresh.
@MainActor
final class FollowedShows: ObservableObject {
    static let shared = FollowedShows()

    /// What the provider says about one show right now.
    struct Snapshot: Sendable {
        var episodes: [EpisodeRef]
        var poster = "", backdrop = "", plot = ""
        var facts: [String] = []
        init(episodes: [EpisodeRef], poster: String = "", backdrop: String = "", plot: String = "", facts: [String] = []) {
            self.episodes = episodes; self.poster = poster; self.backdrop = backdrop; self.plot = plot; self.facts = facts
        }
        init(_ d: Details) { self.init(episodes: EpisodeDiff.refs(d), poster: d.poster, backdrop: d.backdrop, plot: d.plot, facts: d.facts) }
    }
    private struct Cache: Codable { var checkedAt: Date?; var shows: [NewShow] }

    /// The shows with new episodes found by the last refresh (a stored copy, so Home draws at once).
    @Published private(set) var shows: [NewShow] = []
    private(set) var checkedAt: Date?
    /// Reads one show from the provider; set by `configure(catalog:)`.
    var fetch: (@MainActor (MediaItem) async -> Snapshot?)?
    var now: () -> Date = { Date() }
    /// Season to open on the next show page of this show (set by a tap on the row or the hero).
    var seasonHint: [String: String] = [:]

    private let defaults: UserDefaults
    private let accountId: () -> String
    private var account = ""
    private var seen: [String: SeenRecord] = [:]
    private var refreshing = false
    private var pending: Set<String> = []
    private static let maxRecords = 300

    init(defaults: UserDefaults = .standard, accountId: @escaping () -> String = { AccountVault.activeId }) {
        self.defaults = defaults; self.accountId = accountId
        reloadIfAccountChanged()
    }

    /// Reads the shows from the active catalogue (once per catalogue object).
    func configure(catalog: Catalog) {
        fetch = { [weak catalog] item in
            guard let catalog, let d = await catalog.details(MediaItem(kind: .series, id: item.id, name: item.name, img: item.img)) else { return nil }
            return Snapshot(d)
        }
    }

    // MARK: storage

    private var suffix: String { account == "default" ? "" : "@" + account }
    private func reloadIfAccountChanged() {
        let id = accountId()
        guard id != account else { return }
        account = id
        if let d = defaults.data(forKey: "nx.seen" + suffix), let v = try? JSONDecoder().decode([String: SeenRecord].self, from: d) { seen = v } else { seen = [:] }
        if let d = defaults.data(forKey: "nx.updates" + suffix), let c = try? JSONDecoder().decode(Cache.self, from: d) { shows = c.shows; checkedAt = c.checkedAt }
        else { shows = []; checkedAt = nil }
    }
    private func saveSeen() {
        if seen.count > Self.maxRecords {
            let keep = seen.sorted { $0.value.at > $1.value.at }.prefix(Self.maxRecords).map(\.key)
            seen = seen.filter { keep.contains($0.key) }
        }
        if let d = try? JSONEncoder().encode(seen) { defaults.set(d, forKey: "nx.seen" + suffix) }
    }
    private func saveCache() {
        if let d = try? JSONEncoder().encode(Cache(checkedAt: checkedAt, shows: shows)) { defaults.set(d, forKey: "nx.updates" + suffix) }
    }

    // MARK: reading

    func hasRecord(_ seriesId: String) -> Bool { reloadIfAccountChanged(); return seen[seriesId] != nil }
    func seenIds(_ seriesId: String) -> Set<String>? { reloadIfAccountChanged(); return seen[seriesId].map { Set($0.ids) } }
    /// The shows with new episodes that are still followed.
    func visible(followed: [MediaItem]) -> [NewShow] {
        reloadIfAccountChanged()
        let ids = Set(followed.map(\.id))
        return shows.filter { ids.contains($0.id) }
    }
    func takeSeasonHint(_ seriesId: String) -> String? { seasonHint.removeValue(forKey: seriesId) }

    // MARK: recording (rule 2)

    /// Records everything the provider lists now as seen; the show leaves the "New episodes" row.
    func record(_ seriesId: String, episodes: [EpisodeRef]) {
        reloadIfAccountChanged()
        guard !episodes.isEmpty else { return }
        seen[seriesId] = SeenRecord(ids: EpisodeDiff.merged(seen[seriesId]?.ids ?? [], with: episodes), at: now())
        saveSeen()
        if shows.contains(where: { $0.id == seriesId }) { shows.removeAll { $0.id == seriesId }; saveCache() }
    }

    /// A show page opens: the episodes not seen yet (for the "NEW" pills of this visit); the set is recorded now.
    func opened(_ series: MediaItem, snapshot: Snapshot) -> Set<String> {
        reloadIfAccountChanged()
        let cur = snapshot.episodes
        let fresh: Set<String>
        if let s = seen[series.id], !EpisodeDiff.reindexed(current: cur, seen: Set(s.ids)) {
            fresh = Set(EpisodeDiff.newEpisodes(current: cur, seen: Set(s.ids)).map(\.id))
        } else { fresh = [] }
        record(series.id, episodes: cur)
        return fresh
    }

    /// The show joined My List: record what it has now, so only later episodes count as new.
    func noteFollowed(_ series: MediaItem) {
        reloadIfAccountChanged()
        guard seen[series.id] == nil, pending.insert(series.id).inserted else { return }
        Task {
            if let s = await fetch?(series) { record(series.id, episodes: s.episodes) }
            pending.remove(series.id)
        }
    }

    /// An episode of the show plays: the episodes found new by the last refresh count as seen.
    func played(_ series: MediaItem) {
        reloadIfAccountChanged()
        if let n = shows.first(where: { $0.id == series.id }) { record(series.id, episodes: n.episodes) }
        else if seen[series.id] == nil { noteFollowed(series) }
    }

    // MARK: refresh (rule 3)

    /// Reads the provider's series info for each followed show (at most 30, 3 at a time) and keeps the shows with new episodes.
    /// Runs at most once an hour unless `force`.
    func refresh(followed: [MediaItem], force: Bool = false) async {
        reloadIfAccountChanged()
        let list = Array(followed.prefix(EpisodeDiff.cap))
        guard let fetch, !refreshing else { return }
        if !force, let at = checkedAt, now().timeIntervalSince(at) < EpisodeDiff.maxAge { return }
        refreshing = true
        defer { refreshing = false }
        var results: [String: Snapshot] = [:]
        var i = 0
        while i < list.count {
            let chunk = list[i..<min(i + EpisodeDiff.width, list.count)]
            i += EpisodeDiff.width
            await withTaskGroup(of: (String, Snapshot?).self) { group in
                for it in chunk { group.addTask { (it.id, await fetch(it)) } }
                for await (id, snap) in group { if let snap { results[id] = snap } }
            }
        }
        if !list.isEmpty && results.isEmpty { return }   // nothing could be read (offline, catalogue not loaded): try again next time
        var out: [NewShow] = []
        for it in list {
            guard let snap = results[it.id], !snap.episodes.isEmpty else {
                if let old = shows.first(where: { $0.id == it.id }) { out.append(old) }   // a failed read keeps what was known
                continue
            }
            let cur = snap.episodes
            guard let s = seen[it.id] else { seen[it.id] = SeenRecord(ids: cur.map(\.id), at: now()); continue }   // first sight: baseline
            if EpisodeDiff.reindexed(current: cur, seen: Set(s.ids)) { seen[it.id] = SeenRecord(ids: cur.map(\.id), at: now()); continue }
            let fresh = EpisodeDiff.newEpisodes(current: cur, seen: Set(s.ids))
            guard !fresh.isEmpty else { continue }
            var series = it
            if !snap.poster.isEmpty { series.img = snap.poster }
            out.append(NewShow(series: series, episodes: fresh, backdrop: snap.backdrop, plot: snap.plot, facts: snap.facts))
        }
        saveSeen()
        shows = out
        checkedAt = now()
        saveCache()
    }
}
