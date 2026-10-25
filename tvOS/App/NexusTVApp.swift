import SwiftUI

@main
struct NexusTVApp: App {
    @StateObject private var nav = Nav()
    @StateObject private var settings = Settings()
    @StateObject private var catalog = Catalog()
    @StateObject private var user = UserStore()

    init() {
        #if DEBUG
        // test hook: -NXResetAccounts YES starts like a new install (no account: the onboarding screen)
        if UserDefaults.standard.bool(forKey: "NXResetAccounts") { AccountVault.removeAll() }
        // test hook: -NXClearCache YES starts with no cached lists (the search index is prepared again)
        if UserDefaults.standard.bool(forKey: "NXClearCache") { DiskCache.clear() }
        // test hook: -NXResetOSub YES starts with no OpenSubtitles account
        if UserDefaults.standard.bool(forKey: "NXResetOSub") { OpenSubtitles.resetForTests() }
        // test hook: -NXResetSubDelay YES forgets every subtitle timing (found or set by hand)
        if UserDefaults.standard.bool(forKey: "NXResetSubDelay") { UserDefaults.standard.removeObject(forKey: "nx.subDelay") }
        #endif
        Metrics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(nav)
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(user)
                .preferredColorScheme(.dark)
                .task { await catalog.start(languages: settings.languages) }
                .onChange(of: settings.languages) { _, l in catalog.languagesChanged(l) }
                .onChange(of: catalog.activeId) { _, id in user.load(account: id) }
        }
    }
}

/// What to play: one item, where to start, and (for live) the list that up/down zaps through.
struct PlayRequest: Identifiable {
    let id = UUID()
    var item: MediaItem
    var startMs: Int = 0
    var list: [MediaItem] = []
    var index: Int = 0
    var subtitle: String = ""
    /// Episodes that follow this one (Next episode button, auto-play at the end).
    var next: [MediaItem] = []
    /// Picture for the loading card.
    var picture: String = ""
}

@MainActor
final class Nav: ObservableObject {
    /// The last tab is kept, so reopening the app lands where the owner left.
    @Published var tab: TabID = TabID(rawValue: UserDefaults.standard.string(forKey: "nx.lastTab") ?? "") ?? .home {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "nx.lastTab"); if tab != oldValue { browse = [] } }
    }
    /// Lists and families opened from a browse shelf (Menu goes back one).
    @Published var browse: [BrowseRef] = []
    /// Page-level language of Films and Series ("EN" or "FR"); list names carry no language tag.
    @Published var browseLang: String = UserDefaults.standard.string(forKey: "nx.browseLang") ?? "EN" {
        didSet { UserDefaults.standard.set(browseLang, forKey: "nx.browseLang") }
    }
    @Published var detail: [MediaItem] = []
    /// Home: the row holding the tile being moved.
    @Published var movingRow: String? = nil
    /// Home: the one tile being moved inside `movingRow` (it lifts and wiggles; left/right slide it).
    @Published var movingTile: String? = nil
    func stopMoving() { movingRow = nil; movingTile = nil }
    /// Live TV: open the guide on this country (set by a Home "All channels" tile).
    @Published var guideCountry: String? = nil
    @Published var playing: PlayRequest? = nil
    /// The long-press menu of a series tile (tvOS/Views/SeriesMenu.swift).
    @Published var seriesMenu: SeriesMenuRequest? = nil
    @Published var searchSeed: String = ""
    /// Bumped to ask the menu bar to take focus.
    @Published var focusMenuTick = 0

    init() {
        // Launch arguments for screenshots and tests, e.g. -NXTab live, -NXOpen series:1234, -NXSearch friends, -NXPlay film:123:mkv
        let d = UserDefaults.standard
        if let t = d.string(forKey: "NXTab"), let id = TabID(rawValue: t) { tab = id }
        if let s = d.string(forKey: "NXSearch") { searchSeed = s; tab = .search }
        // -NXBrowse series|svc:Netflix|Netflix opens a family or a service's lists on top of its tab
        if let b = d.string(forKey: "NXBrowse") {
            let p = b.split(separator: "|").map(String.init)
            if p.count == 3, let k = ItemKind(rawValue: p[0]) { browse = [BrowseRef(kind: k, key: p[1], title: p[2])] }
        }
        if let o = d.string(forKey: "NXOpen") {
            let p = o.split(separator: ":").map(String.init)
            if p.count >= 2, let k = ItemKind(rawValue: p[0]) { detail = [MediaItem(kind: k, id: p[1], name: p.count > 2 ? p[2] : "")] }
        }
        if let o = d.string(forKey: "NXPlay") {
            let p = o.split(separator: ":").map(String.init)
            if p.count >= 2, let k = ItemKind(rawValue: p[0]) {
                let start = Int(d.string(forKey: "NXStart") ?? "") ?? 0
                var it = MediaItem(kind: k, id: p[1], name: d.string(forKey: "NXName") ?? "Test stream", ext: p.count > 2 ? p[2] : "")
                if let sr = d.string(forKey: "NXSeries") {     // "45370:House Of Guinness"
                    let q = sr.split(separator: ":", maxSplits: 1).map(String.init)
                    it.seriesId = q.first; it.seriesName = q.count > 1 ? q[1] : nil
                }
                playing = PlayRequest(item: it, startMs: start)
            }
        }
    }

    func open(_ it: MediaItem) { detail.append(it) }
    func play(_ it: MediaItem, startMs: Int = 0, list: [MediaItem] = [], index: Int = 0, subtitle: String = "", next: [MediaItem] = [], picture: String = "") {
        playing = PlayRequest(item: it, startMs: startMs, list: list, index: index, subtitle: subtitle, next: next, picture: picture.isEmpty ? it.img : picture)
    }
    func openGuide(_ cc: String) { guideCountry = cc; detail = []; browse = []; tab = .live }
}
