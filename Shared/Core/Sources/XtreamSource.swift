import Foundation

/// The Xtream Codes code path of the first builds, behind the LibrarySource protocol.
final class XtreamSource: LibrarySource {
    let api: Xtream
    var type: SourceType { .xtream }
    init(account: Account) { api = Xtream(account: account) }

    func liveCategories() async throws -> [XCategory] { try await api.list(XCategory.self, "get_live_categories") }
    func vodCategories() async throws -> [XCategory] { try await api.list(XCategory.self, "get_vod_categories") }
    func seriesCategories() async throws -> [XCategory] { try await api.list(XCategory.self, "get_series_categories") }

    func liveStreams(category: String?) async throws -> [XLive] { try await list(XLive.self, "get_live_streams", category, "live_raw.json") }
    func vodStreams(category: String?) async throws -> [XVod] { try await list(XVod.self, "get_vod_streams", category, "vod_raw.json") }
    func seriesList(category: String?) async throws -> [XSeries] { try await list(XSeries.self, "get_series", category, "series_raw.json") }

    /// One category is a small answer; the whole list goes to a file first, so the app never holds two copies in memory.
    private func list<T: Decodable>(_ type: T.Type, _ action: String, _ category: String?, _ tmp: String) async throws -> [T] {
        if let category { return try await api.list(T.self, action, ["category_id": category]) }
        let file = DiskCache.url(tmp)
        try await api.download(action, to: file)
        return await Task.detached(priority: .utility) { () -> [T] in
            defer { try? FileManager.default.removeItem(at: file) }
            guard let d = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
            return (try? JSONDecoder().decode([T].self, from: d)) ?? []
        }.value
    }

    func info(film: Bool, id: String) async throws -> [String: Any] {
        try await api.json(film ? "get_vod_info" : "get_series_info", film ? ["vod_id": id] : ["series_id": id])
    }

    func streamURL(kind: ItemKind, id: String, ext: String) -> URL? {
        var a = api
        // test hook: -NXStreamBase http://127.0.0.1:18888 sends the stream (only the stream) through a local stand-in
        if let b = UserDefaults.standard.string(forKey: "NXStreamBase") { a = Xtream(account: Account(server: b, username: a.account.username, password: a.account.password)) }
        switch kind {
        case .live: return a.liveURL(id)
        case .film: return a.filmURL(id, ext)
        case .episode: return a.episodeURL(id, ext)
        case .series: return nil
        }
    }
}
