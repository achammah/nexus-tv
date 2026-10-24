import SwiftUI

/// Nexus TV for Mac: a library window (sidebar + pages, layout 1a) and a separate player window.
/// Shares Core (Xtream client, catalogue, search, caches, stores, OpenSubtitles) and the VLC controller with
/// the Apple TV app.
@main
struct NexusTVMacApp: App {
    @StateObject private var catalog = Catalog()
    @StateObject private var settings = Settings()
    @StateObject private var user = UserStore()
    @StateObject private var nav = MacNav()

    init() {
        #if DEBUG
        // test hooks, as on the Apple TV: a new install, empty lists
        if UserDefaults.standard.bool(forKey: "NXResetAccounts") { AccountVault.removeAll() }
        if UserDefaults.standard.bool(forKey: "NXClearCache") { DiskCache.clear() }
        if UserDefaults.standard.bool(forKey: "NXResetOSub") { OpenSubtitles.resetForTests() }
        // screenshots: NXTV_SEED_ACCOUNT_FILE (3 lines: server, username, password) signs in when no account exists
        if let f = ProcessInfo.processInfo.environment["NXTV_SEED_ACCOUNT_FILE"], AccountVault.list().isEmpty,
           let t = try? String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8) {
            let l = t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if l.count >= 3 { AccountVault.save([StoredAccount(id: "default", name: "My IPTV", server: Account(server: l[0], username: l[1], password: l[2]).base, username: l[1], password: l[2])]) }
        }
        #endif
    }

    var body: some Scene {
        Window("Nexus TV", id: "library") {
            LibraryWindow()
                .environmentObject(catalog).environmentObject(settings).environmentObject(user).environmentObject(nav)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await catalog.start(languages: settings.languages) }
                .onChange(of: settings.languages) { _, l in catalog.languagesChanged(l) }
                .onChange(of: catalog.activeId) { _, id in user.load(account: id) }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Search") { nav.go(.search); nav.focusSearch += 1 }.keyboardShortcut("f", modifiers: .command)
            }
        }

        SwiftUI.Settings {
            MacSettingsPane()
                .environmentObject(catalog).environmentObject(settings).environmentObject(user)
                .frame(width: 640, height: 520)
                .preferredColorScheme(.dark)
        }
    }
}

/// What the player window opens: one item, where to start, the live list to zap through, the episodes that follow.
struct MacPlay: Codable, Hashable {
    var item: MediaItem
    var startMs: Int = 0
    var list: [MediaItem] = []
    var index: Int = 0
    var next: [MediaItem] = []
    var picture: String = ""
}

/// Where the library window is: a sidebar page, plus the detail pages opened on top of it, with back and forward.
@MainActor
final class MacNav: ObservableObject {
    enum Page: Hashable {
        case home, live(String), films, series, mylist, search, account, settings
        /// One whole list (its posters or channels), or every card of one family or service ("See all").
        case list(BrowseRef), family(BrowseRef)
        var title: String {
            switch self {
            case .home: "Home"; case .live(let cc): cc.isEmpty ? "Live TV" : Countries.name(cc); case .films: "Films"
            case .series: "Series"; case .mylist: "My List"; case .search: "Search"; case .account: "IPTV account"; case .settings: "Settings"
            case .list(let r), .family(let r): r.title
            }
        }
        /// The sidebar page a list or family belongs to (it stays selected).
        var root: Page {
            switch self {
            case .list(let r), .family(let r): r.kind == .live ? .live(r.cc) : r.kind == .film ? .films : .series
            default: self
            }
        }
    }
    /// Page-level language of the Films and Series pages ("EN" or "FR"); the list names carry no language tag.
    @Published var browseLang: String = UserDefaults.standard.string(forKey: "nx.browseLang") ?? "EN" {
        didSet { UserDefaults.standard.set(browseLang, forKey: "nx.browseLang") }
    }
    struct Spot: Hashable { var page: Page; var detail: MediaItem? }

    @Published private(set) var spot = Spot(page: .home, detail: nil)
    @Published var query = ""
    @Published var focusSearch = 0
    private var back: [Spot] = []
    private var fwd: [Spot] = []

    init() {
        // launch arguments for tests and screenshots: -NXPage films, -NXOpen series:1234:Name, -NXSearch text
        let d = UserDefaults.standard
        if let p = d.string(forKey: "NXPage") { spot.page = Self.page(p) }
        if let s = d.string(forKey: "NXSearch") { query = s; spot.page = .search }
        if let o = d.string(forKey: "NXOpen") {
            let p = o.split(separator: ":", maxSplits: 2).map(String.init)
            if p.count >= 2, let k = ItemKind(rawValue: p[0]) { spot.detail = MediaItem(kind: k, id: p[1], name: p.count > 2 ? p[2] : "") }
        }
    }
    static func page(_ s: String) -> Page {
        switch s {
        case "live": return .live(""); case "films": return .films; case "series": return .series; case "mylist": return .mylist
        case "search": return .search; case "account": return .account; case "settings": return .settings
        default:
            // "family:film:svc:Netflix:Netflix", "family:live:sport:Sports:US" (kind:key:title[:country])
            if s.hasPrefix("family:") {
                let p = s.dropFirst(7).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                if p.count >= 3, let k = ItemKind(rawValue: p[0]) {
                    let key = p[1] == "svc" && p.count >= 4 ? "svc:" + p[2] : p[1], rest = p[1] == "svc" ? Array(p.dropFirst(3)) : Array(p.dropFirst(2))
                    return .family(BrowseRef(kind: k, key: key, title: rest.first ?? key, cc: rest.count > 1 ? rest[1] : ""))
                }
            }
            return s.hasPrefix("live:") ? .live(String(s.dropFirst(5)).uppercased()) : .home
        }
    }

    var page: Page { spot.page }
    var detail: MediaItem? { spot.detail }
    var canBack: Bool { !back.isEmpty }
    var canForward: Bool { !fwd.isEmpty }

    /// What plays inside the window; nil = the pages. Leaving the player returns to the page it came from.
    @Published private(set) var playing: MacPlay?
    func play(_ p: MacPlay) { playing = p }
    func closePlayer() { playing = nil }

    func go(_ p: Page) { closePlayer(); move(to: Spot(page: p, detail: nil)) }
    func open(_ it: MediaItem) { move(to: Spot(page: spot.page, detail: it)) }
    func goBack() { guard let s = back.popLast() else { return }; fwd.append(spot); spot = s }
    func goForward() { guard let s = fwd.popLast() else { return }; back.append(spot); spot = s }
    private func move(to s: Spot) { guard s != spot else { return }; back.append(spot); fwd = []; spot = s }
}
