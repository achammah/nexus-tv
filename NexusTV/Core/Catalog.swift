import Foundation
import SwiftUI

/// Small JSON files in Caches/nexus, each with an age limit.
enum DiskCache {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("nexus", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }
    static func age(_ name: String) -> TimeInterval? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url(name).path), let m = a[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(m)
    }
    static func load<T: Decodable>(_ name: String, maxAge: TimeInterval) -> T? {
        guard let a = age(name), a < maxAge, let d = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ name: String, _ v: T) {
        if let d = try? JSONEncoder().encode(v) { try? d.write(to: url(name), options: .atomic) }
    }
    /// Decoding and encoding big caches never runs on the main thread.
    static func loadOff<T: Decodable & Sendable>(_ name: String, maxAge: TimeInterval) async -> T? {
        await Task.detached(priority: .utility) { () -> T? in load(name, maxAge: maxAge) }.value
    }
    static func saveOff<T: Encodable & Sendable>(_ name: String, _ v: T) {
        Task.detached(priority: .background) { save(name, v) }
    }
    static func clear() { try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
}

/// A film, series or channel outside the chosen languages / countries: names only, searched after the main index.
struct MoreEntry: Codable, Hashable, Sendable {
    let i: String, n: String, l: String, k: String, x: String   // id, name, badge (language tag or country code), kind (f/s/c), extension
}

/// The searchable films + series for the chosen languages (built in the background, refreshed daily).
struct SearchIndex: Codable, Sendable {
    var films: [IndexEntry] = []
    var series: [IndexEntry] = []
    var languages: [String] = []
}

enum LoadState: Equatable { case idle, loading, ready, failed(String) }

@MainActor
final class Catalog: ObservableObject {
    static let day: TimeInterval = 24 * 3600

    @Published private(set) var accounts: [StoredAccount] = AccountVault.list()
    @Published private(set) var activeId: String = AccountVault.active()?.id ?? "default"
    var account: Account? { (accounts.first { $0.id == activeId } ?? accounts.first)?.account }
    var activeName: String { (accounts.first { $0.id == activeId } ?? accounts.first)?.name ?? "" }
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var liveCats: [XCategory] = [] { didSet { groupMemo = [:] } }
    @Published private(set) var vodCats: [XCategory] = [] { didSet { libMemo = [:] } }
    @Published private(set) var seriesCats: [XCategory] = [] { didSet { libMemo = [:] } }
    private var groupMemo: [String: [XCategory]] = [:]
    private var libMemo: [String: [XCategory]] = [:]
    /// Names of every other language (Afro Samurai sits only in |DE| ANIME…), loaded the first time a search needs it.
    private var more: [MoreEntry]? = nil
    @Published private(set) var hero: [HeroItem] = []
    @Published private(set) var newFilms: [MediaItem] = []
    @Published private(set) var topSeries: [MediaItem] = []
    @Published private(set) var liveIndex: [String: [Channel]] = [:]   // category id -> channels (whole catalogue, once loaded)
    @Published private(set) var index = SearchIndex()
    @Published private(set) var indexState: LoadState = .idle
    /// While the search index is built from scratch (first launch, new account): what it is on, for a small line on screen.
    @Published private(set) var indexProgress: String? = nil
    var needsAccount: Bool { accounts.isEmpty }
    @Published private(set) var counts: [String: Int] = [:]             // film/series category id -> titles

    private var channelCache: [String: [Channel]] = [:]
    private var itemCache: [String: [MediaItem]] = [:]
    private var languages: [String] = Settings.defaultLanguages

    var api: Xtream? { account.map(Xtream.init) }

    // MARK: start-up

    func start(languages: [String]) async {
        self.languages = languages
        guard let api else { state = .failed("No account. Open Settings › Account."); return }
        state = .loading
        do {
            async let l: [XCategory] = cachedList("live_categories.json") { try await api.list(XCategory.self, "get_live_categories") }
            async let v: [XCategory] = cachedList("vod_categories.json") { try await api.list(XCategory.self, "get_vod_categories") }
            async let s: [XCategory] = cachedList("series_categories.json") { try await api.list(XCategory.self, "get_series_categories") }
            (liveCats, vodCats, seriesCats) = try await (l, v, s)
            state = liveCats.isEmpty && vodCats.isEmpty ? .failed("The server sent no categories. Check Settings › Account.") : .ready
        } catch {
            if case Xtream.Failure.http(let code) = error {
                state = .failed("The provider refused the request (HTTP \(code)). Check the subscription in Settings › Accounts.")
            } else {
                state = .failed("Could not reach the server (\(error.localizedDescription)).")
            }
            return
        }
        await loadHome()
        Metrics.shared.mark("catalog.home")
        // the big lists come later and off the main thread: Home is on screen first
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await ensureLiveIndex() }
        Task { try? await Task.sleep(nanoseconds: 6_000_000_000); await buildIndex(force: false) }
    }

    /// Loads the first category of Live TV, Films and Series in the background, so opening those screens is instant.
    func prewarm(country: String, languages: [String]) async {
        if let g = liveGroups(country).first { _ = await channels(g.id) }
        if let f = libraryCategories(.film, languages: languages).first { _ = await items(.film, f.id) }
        if let s = libraryCategories(.series, languages: languages).first { _ = await items(.series, s.id) }
        Metrics.shared.mark("catalog.prewarmed")
    }

    /// Switch to another saved account: every cache is dropped and the catalogue reloads from its provider.
    func use(_ id: String, languages: [String]) async {
        AccountVault.activeId = id
        activeId = id
        await reload(languages: languages)
    }
    func addAccount(_ a: StoredAccount) {
        accounts.append(a); AccountVault.save(accounts)
    }
    /// First launch: the first account becomes the active one and the catalogue loads.
    func onboard(_ a: StoredAccount, languages: [String]) async {
        addAccount(a)
        await use(a.id, languages: languages)
    }
    func removeAccount(_ id: String) {
        guard id != activeId else { return }
        accounts.removeAll { $0.id == id }; AccountVault.save(accounts)
    }
    func reload(languages: [String]) async {
        DiskCache.clear()
        channelCache = [:]; itemCache = [:]; liveIndex = [:]; index = SearchIndex(); counts = [:]
        hero = []; newFilms = []; topSeries = []; liveCats = []; vodCats = []; seriesCats = []
        await start(languages: languages)
    }

    func languagesChanged(_ langs: [String]) {
        guard langs != languages else { return }
        languages = langs
        Task { await buildIndex(force: true) }
    }

    private func cachedList<T: Codable>(_ name: String, _ fetch: () async throws -> [T]) async throws -> [T] {
        if let c: [T] = await DiskCache.loadOff(name, maxAge: Self.day), !c.isEmpty { return c }
        let v = try await fetch()
        if !v.isEmpty { DiskCache.saveOff(name, v) }
        return v
    }

    // MARK: live

    private static let lateGroup = try! NSRegularExpression(pattern: "PPV|VIP|EVENT|24/7|RAW|PLAY\\b|PRIME|MAX|DAZN|ESPN|PACKAGE|NETWORK HULU")

    /// Live categories of one country, everyday channels first, pay-per-view and event feeds last; no replay groups.
    func liveGroups(_ cc: String) -> [XCategory] {
        if let g = groupMemo[cc] { return g }
        let g = liveGroups0(cc)
        groupMemo[cc] = g
        return g
    }
    private func liveGroups0(_ cc: String) -> [XCategory] {
        let mine = liveCats.filter { Clean.country($0.name) == cc && $0.name.range(of: "REPLAY", options: .caseInsensitive) == nil }
        func late(_ c: XCategory) -> Int { Self.lateGroup.firstMatch(in: c.name, range: NSRange(c.name.startIndex..., in: c.name)) == nil ? 0 : 1 }
        return mine.enumerated().sorted { (late($0.element), $0.offset) < (late($1.element), $1.offset) }.map(\.element)
    }

    /// Countries the provider has, with their number of groups (for Settings).
    var liveCountries: [(String, Int)] {
        var c: [String: Int] = [:]
        for cat in liveCats { if let cc = Clean.country(cat.name) { c[cc, default: 0] += 1 } }
        return c.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func channels(_ cat: String) async -> [Channel] {
        if let c = liveIndex[cat] { return c }
        if let c = channelCache[cat] { return c }
        guard let api else { return [] }
        let raw = (try? await api.list(XLive.self, "get_live_streams", ["category_id": cat])) ?? []
        let c = Self.channels(from: raw)[cat] ?? []
        channelCache[cat] = c
        return c
    }

    nonisolated private static func channels(from raw: [XLive]) -> [String: [Channel]] {
        var out: [String: [Channel]] = [:]
        for s in raw where !s.adult {
            let n = Clean.title(s.name)
            if n.isEmpty || Clean.isSeparator(n) { continue }
            out[s.categoryId, default: []].append(Channel(id: s.id, name: n, icon: s.icon, categoryId: s.categoryId))
        }
        return out
    }

    /// The whole live list, loaded once; a second caller waits for the first load instead of downloading again.
    private var liveTask: Task<Void, Never>?
    func ensureLiveIndex() async {
        if !liveIndex.isEmpty { return }
        if let t = liveTask { await t.value; return }
        let t = Task { await loadLiveIndex() }
        liveTask = t
        await t.value
        liveTask = nil
    }

    /// Live category id -> its country code ("BE"; "OTHER" when the name has no code), for every live category.
    func liveCodes() -> [String: String] {
        Dictionary(liveCats.map { ($0.id, Clean.country($0.name) ?? "OTHER") }, uniquingKeysWith: { a, _ in a })
    }

    /// Every live category grouped by country code, in the provider's order (Settings › Channels).
    func liveByCountry() -> [(code: String, cats: [XCategory])] {
        var by: [String: [XCategory]] = [:], order: [String] = []
        for c in liveCats {
            let code = Clean.country(c.name) ?? "OTHER"
            if by[code] == nil { order.append(code) }
            by[code, default: []].append(c)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    /// The whole live list (≈54k channels) once a day, to fill counts and channel search.
    private func loadLiveIndex() async {
        if let c: [String: [Channel]] = await DiskCache.loadOff("live_index.json", maxAge: Self.day), !c.isEmpty { liveIndex = c; return }
        guard let api else { return }
        let file = DiskCache.url("live_raw.json")
        do {
            try await api.download("get_live_streams", to: file)
            let grouped = await Task.detached(priority: .utility) { () -> [String: [Channel]] in
                defer { try? FileManager.default.removeItem(at: file) }
                guard let d = try? Data(contentsOf: file, options: .mappedIfSafe),
                      let raw = try? JSONDecoder().decode([XLive].self, from: d) else { return [:] }
                return Catalog.channels(from: raw)
            }.value
            if !grouped.isEmpty { liveIndex = grouped; DiskCache.saveOff("live_index.json", grouped) }
        } catch { /* the guide keeps loading one category at a time */ }
    }

    func liveRowGroup(_ cc: String) -> XCategory? {
        let groups = liveGroups(cc)
        let preferred = ["BE": "ALGEMEEN", "FR": "FRANCE FHD", "UK": "ENTERTAINMENT", "US": "ENTERTAINMENT"][cc]
        if let p = preferred, let g = groups.first(where: { Clean.category($0.name).uppercased() == p }) { return g }
        return groups.first
    }

    /// A country's Home row: the first everyday channels across its groups, one tile per channel name
    /// (HD/FHD/HEVC copies folded together). Returns the tiles and the country's channel count when known.
    func countryRow(_ cc: String, max: Int = 24) async -> (items: [MediaItem], total: Int?) {
        let groups = liveGroups(cc)
        var seen = Set<String>(), out: [MediaItem] = []
        for g in groups where out.count < max {
            let label = Countries.name(cc) + " · " + Clean.titleCase(Clean.category(g.name))
            for c in await channels(g.id) where out.count < max {
                if seen.insert(Self.foldName(c.name)).inserted {
                    out.append(MediaItem(kind: .live, id: c.id, name: c.name, img: c.icon, sub: label))
                }
            }
        }
        let total = liveIndex.isEmpty ? nil : groups.reduce(0) { $0 + (liveIndex[$1.id]?.count ?? 0) }
        return (out, total)
    }
    nonisolated static func foldName(_ n: String) -> String {
        n.lowercased().replacingOccurrences(of: "\\s+(fhd|uhd|hd|sd|hevc|4k|raw|vip|h265|1080p?|720p?)\\b", with: "", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// Tiles of a category the owner added as a Home row.
    func listItems(_ l: HomeList) async -> [MediaItem] {
        switch l.t {
        case .live: return await channels(l.id).map { MediaItem(kind: .live, id: $0.id, name: $0.name, img: $0.icon, sub: l.name) }
        case .film, .series: return await items(l.t, l.id)
        case .episode: return []
        }
    }

    // MARK: films + series

    /// Film or series categories for the chosen languages: multi-language and untagged first, then English, then French.
    func libraryCategories(_ kind: ItemKind, languages: [String]) -> [XCategory] {
        let key = kind.rawValue + languages.joined(separator: ",")
        if let m = libMemo[key] { return m }
        let m = libraryCategories0(kind, languages: languages)
        libMemo[key] = m
        return m
    }
    private func libraryCategories0(_ kind: ItemKind, languages: [String]) -> [XCategory] {
        let src = kind == .film ? vodCats : seriesCats
        let order = ["MULTI": 0, "": 0, "EN": 1, "FR": 2]
        return src.enumerated()
            .filter { languages.contains(Clean.tag($0.element.name) ?? "") }
            .filter { !$0.element.name.localizedCaseInsensitiveContains("ADULT") && !$0.element.name.contains("XXX") && !$0.element.name.contains("18+") }
            .sorted { (order[Clean.tag($0.element.name) ?? ""] ?? 3, $0.offset) < (order[Clean.tag($1.element.name) ?? ""] ?? 3, $1.offset) }
            .map(\.element)
    }

    func items(_ kind: ItemKind, _ cat: String) async -> [MediaItem] {
        let key = kind.rawValue + ":" + cat
        if let c = itemCache[key] { return c }
        guard let api else { return [] }
        var out: [MediaItem] = []
        // the category name rides along in `sub` (it can say "ENG SUB")
        let catName = (kind == .film ? vodCats : seriesCats).first { $0.id == cat }?.name ?? ""
        if kind == .film {
            let raw = (try? await api.list(XVod.self, "get_vod_streams", ["category_id": cat])) ?? []
            out = raw.filter { !$0.adult }.map { MediaItem(kind: .film, id: $0.id, name: Clean.title($0.name), img: $0.icon, ext: $0.ext, sub: catName) }
        } else {
            let raw = (try? await api.list(XSeries.self, "get_series", ["category_id": cat])) ?? []
            out = raw.filter { !$0.adult }.map { MediaItem(kind: .series, id: $0.id, name: Clean.title($0.name), img: $0.cover, sub: catName) }
        }
        if !out.isEmpty { itemCache[key] = out }
        return out
    }

    private func loadHome() async {
        guard let api else { return }
        let newCat = vodCats.first { $0.name.trimmingCharacters(in: .whitespaces) == "|EN| NEW RELEASED" } ?? vodCats.first { Clean.tag($0.name) == "EN" }
        let topCat = seriesCats.first { $0.name.trimmingCharacters(in: .whitespaces) == "|EN| TOP SERIES" } ?? seriesCats.first { Clean.tag($0.name) == "EN" }
        if let c: [MediaItem] = await DiskCache.loadOff("home_films.json", maxAge: Self.day / 4),
           let s: [MediaItem] = await DiskCache.loadOff("home_series.json", maxAge: Self.day / 4),
           let h: [HeroCache] = await DiskCache.loadOff("home_hero.json", maxAge: Self.day / 4) {
            newFilms = c; topSeries = s; hero = h.map(\.item)
            return
        }
        let newId = newCat?.id ?? "", topId = topCat?.id ?? ""
        async let films: [XVod] = newId.isEmpty ? [] : ((try? await api.list(XVod.self, "get_vod_streams", ["category_id": newId])) ?? [])
        async let series: [XSeries] = topId.isEmpty ? [] : ((try? await api.list(XSeries.self, "get_series", ["category_id": topId])) ?? [])
        let (f, s) = await (films, series)
        var seen = Set<String>()
        newFilms = f.filter { !$0.adult && !$0.icon.isEmpty }.compactMap { v -> MediaItem? in
            let t = Clean.title(v.name)
            return seen.insert(t).inserted ? MediaItem(kind: .film, id: v.id, name: t, img: v.icon, ext: v.ext) : nil
        }.prefix(30).map { $0 }
        topSeries = s.filter { !$0.adult && !$0.cover.isEmpty }.prefix(30).map { MediaItem(kind: .series, id: $0.id, name: Clean.title($0.name), img: $0.cover) }
        hero = s.filter { x in
            let back = x.backdrops.first ?? ""
            return back.contains("tmdb") && !x.plot.isEmpty && (Double(x.rating) ?? 0) >= 7
        }.prefix(5).map { x in
            HeroItem(id: x.id, title: Clean.display(x.name.components(separatedBy: " (").first ?? x.name), year: x.year,
                     genre: x.genre.components(separatedBy: CharacterSet(charactersIn: "/,")).first?.trimmingCharacters(in: .whitespaces) ?? "",
                     rating: x.rating, plot: x.plot, backdrop: x.backdrops.first ?? "", cover: x.cover)
        }
        DiskCache.saveOff("home_films.json", newFilms)
        DiskCache.saveOff("home_series.json", topSeries)
        DiskCache.saveOff("home_hero.json", hero.map(HeroCache.init))
    }

    // MARK: search index

    /// Films + series of the chosen languages: id, name, picture, category. Built from the two full lists, once a day.
    func buildIndex(force: Bool) async {
        if indexState == .loading { return }
        Metrics.shared.mark("index.build force=\(force)")
        if !force, let c: SearchIndex = await DiskCache.loadOff("search_index.json", maxAge: Self.day), c.languages == languages, !c.films.isEmpty {
            await setIndex(c); return
        }
        // the categories decide what is "chosen" and what is "other": never build before they are loaded
        guard let api, !vodCats.isEmpty, !seriesCats.isEmpty else { return }
        indexState = .loading
        indexProgress = "Preparing search · films"
        defer { indexProgress = nil }
        let langs = languages
        let keepVod = Set(vodCats.filter { langs.contains(Clean.tag($0.name) ?? "") }.map(\.id))
        let keepSer = Set(seriesCats.filter { langs.contains(Clean.tag($0.name) ?? "") }.map(\.id))
        // other languages: category id -> its tag ("DE"); adult groups left out
        let adult = { (n: String) in n.localizedCaseInsensitiveContains("ADULT") || n.contains("XXX") || n.contains("18+") }
        let otherVod = Dictionary(vodCats.filter { !keepVod.contains($0.id) && !adult($0.name) }.map { ($0.id, Clean.tag($0.name) ?? Clean.country($0.name) ?? "") }, uniquingKeysWith: { a, _ in a })
        let otherSer = Dictionary(seriesCats.filter { !keepSer.contains($0.id) && !adult($0.name) }.map { ($0.id, Clean.tag($0.name) ?? Clean.country($0.name) ?? "") }, uniquingKeysWith: { a, _ in a })
        do {
            let vf = DiskCache.url("vod_raw.json"), sf = DiskCache.url("series_raw.json")
            try await api.download("get_vod_streams", to: vf)
            let (films, moreF) = await Task.detached(priority: .utility) { () -> ([IndexEntry], [MoreEntry]) in
                defer { try? FileManager.default.removeItem(at: vf) }
                guard let d = try? Data(contentsOf: vf, options: .mappedIfSafe), let raw = try? JSONDecoder().decode([XVod].self, from: d) else { return ([], []) }
                let main = raw.filter { !$0.adult && keepVod.contains($0.categoryId) }
                    .map { IndexEntry(id: $0.id, name: Clean.title($0.name), img: $0.icon, cat: $0.categoryId, ext: $0.ext) }
                let more = raw.compactMap { v -> MoreEntry? in
                    guard !v.adult, let l = otherVod[v.categoryId] else { return nil }
                    return MoreEntry(i: v.id, n: Clean.title(v.name), l: l, k: "f", x: v.ext)
                }
                return (main, more)
            }.value
            indexProgress = "Preparing search · series"
            try await api.download("get_series", to: sf)
            let (series, moreS) = await Task.detached(priority: .utility) { () -> ([IndexEntry], [MoreEntry]) in
                defer { try? FileManager.default.removeItem(at: sf) }
                guard let d = try? Data(contentsOf: sf, options: .mappedIfSafe), let raw = try? JSONDecoder().decode([XSeries].self, from: d) else { return ([], []) }
                let main = raw.filter { !$0.adult && keepSer.contains($0.categoryId) }
                    .map { IndexEntry(id: $0.id, name: Clean.title($0.name), img: $0.cover, cat: $0.categoryId, ext: "") }
                let more = raw.compactMap { v -> MoreEntry? in
                    guard !v.adult, let l = otherSer[v.categoryId] else { return nil }
                    return MoreEntry(i: v.id, n: Clean.title(v.name), l: l, k: "s", x: "")
                }
                return (main, more)
            }.value
            let ix = SearchIndex(films: films, series: series, languages: langs)
            await setIndex(ix)
            more = moreF + moreS
            DiskCache.saveOff("search_index.json", ix)
            DiskCache.saveOff("search_more.json", moreF + moreS)
        } catch {
            indexState = .failed(error.localizedDescription)
        }
    }

    private func setIndex(_ ix: SearchIndex) async {
        let c = await Task.detached(priority: .utility) { () -> [String: Int] in
            var c: [String: Int] = [:]
            for e in ix.films { c[e.cat, default: 0] += 1 }
            for e in ix.series { c[e.cat, default: 0] += 1 }
            return c
        }.value
        index = ix
        counts = c
        indexState = .ready
    }

    /// Titles of every other language, loaded once off the main thread (built with the daily index).
    func moreIndex() async -> [MoreEntry] {
        if let m = more, !m.isEmpty { return m }
        if let m: [MoreEntry] = await DiskCache.loadOff("search_more.json", maxAge: Self.day * 2) { more = m; return m }
        if indexState != .loading { await buildIndex(force: true) }
        return more ?? []
    }

    /// Asks for the daily index now (Search or a library screen opened); a no-op once it is loaded.
    func needIndex() { if indexState == .idle { Task { await buildIndex(force: false) } } }

    // MARK: details

    func details(_ it: MediaItem) async -> Details? {
        guard let api else { return nil }
        let isFilm = it.kind == .film
        guard let d = try? await api.json(isFilm ? "get_vod_info" : "get_series_info", isFilm ? ["vod_id": it.id] : ["series_id": it.id]) else { return nil }
        let info = d["info"] as? [String: Any] ?? [:]
        func s(_ o: [String: Any], _ k: String) -> String {
            if let v = o[k] as? String { return v }
            if let v = o[k] as? NSNumber { return v.stringValue }
            return ""
        }
        var out = Details()
        out.name = s(info, "name").isEmpty ? s(d["movie_data"] as? [String: Any] ?? [:], "name") : s(info, "name")
        let year = String((s(info, "releasedate") + s(info, "releaseDate") + s(info, "release_date")).prefix(4))
        let genre = s(info, "genre").components(separatedBy: CharacterSet(charactersIn: "/,")).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let rating = String(s(info, "rating").prefix(3))
        var dur = s(info, "duration")
        if dur.isEmpty, let rt = Int(s(info, "episode_run_time")), rt > 0 { dur = "\(rt) min" }
        if dur.hasPrefix("00:") { dur = String(dur.dropFirst(3)) }
        out.facts = [year, genre, rating.isEmpty || rating == "0" ? "" : "★ " + rating, dur].filter { !$0.isEmpty && !$0.hasPrefix("0") }
        out.plot = s(info, "plot").isEmpty ? s(info, "description") : s(info, "plot")
        out.poster = [s(info, "movie_image"), s(info, "cover"), s(info, "cover_big")].first { !$0.isEmpty } ?? ""
        let backs = (info["backdrop_path"] as? [Any])?.compactMap { $0 as? String } ?? []
        out.backdrop = backs.first ?? [s(info, "cover_big"), s(info, "movie_image"), s(info, "cover"), it.img].first { !$0.isEmpty } ?? ""
        if isFilm, let md = d["movie_data"] as? [String: Any] { out.ext = s(md, "container_extension") }
        if !isFilm {
            var eps: [String: [Episode]] = [:]
            func parse(_ arr: [Any], season fallback: String) {
                for case let e as [String: Any] in arr {
                    let inf = e["info"] as? [String: Any] ?? [:]
                    let season = s(e, "season").isEmpty ? fallback : s(e, "season")
                    let ep = Episode(id: s(e, "id"), num: Int(s(e, "episode_num")) ?? 0,
                                     title: s(e, "title").replacingOccurrences(of: "^.*?-\\s*S\\d+E\\d+\\s*-?\\s*", with: "", options: [.regularExpression, .caseInsensitive]),
                                     ext: s(e, "container_extension"), still: s(inf, "movie_image"), durationSecs: Int(s(inf, "duration_secs")) ?? 0)
                    eps[season, default: []].append(ep)
                }
            }
            if let dict = d["episodes"] as? [String: Any] {
                for (k, v) in dict { if let a = v as? [Any] { parse(a, season: k) } }
            } else if let arr = d["episodes"] as? [Any] {
                for (i, v) in arr.enumerated() { if let a = v as? [Any] { parse(a, season: String(i + 1)) } else { parse([v], season: "1") } }
            }
            for k in eps.keys { eps[k]?.sort { $0.num < $1.num } }
            out.episodes = eps
            out.seasons = eps.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        }
        return out
    }

    // MARK: stream URLs

    func url(_ it: MediaItem) -> URL? {
        guard var api else { return nil }
        // test hook: -NXStreamBase http://127.0.0.1:18888 sends the stream (only the stream) through a local stand-in
        if let b = UserDefaults.standard.string(forKey: "NXStreamBase") { api = Xtream(account: Account(server: b, username: api.account.username, password: api.account.password)) }
        switch it.kind {
        case .live: return api.liveURL(it.id)
        case .film: return api.filmURL(it.id, it.ext)
        case .episode: return api.episodeURL(it.id, it.ext)
        case .series: return nil
        }
    }
}

/// HeroItem is not Codable on purpose (it is a view model); this wraps it for the disk cache.
struct HeroCache: Codable, Sendable {
    let id, title, year, genre, rating, plot, backdrop, cover: String
    init(_ h: HeroItem) { id = h.id; title = h.title; year = h.year; genre = h.genre; rating = h.rating; plot = h.plot; backdrop = h.backdrop; cover = h.cover }
    var item: HeroItem { HeroItem(id: id, title: title, year: year, genre: genre, rating: rating, plot: plot, backdrop: backdrop, cover: cover) }
}
