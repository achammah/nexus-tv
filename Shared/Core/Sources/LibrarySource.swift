import Foundation

/// One way to reach a library. Every adapter answers with the same records the Xtream panel uses
/// (categories, live streams, films, series), so shelves, the Live page, search and resume work unchanged.
protocol LibrarySource: AnyObject, Sendable {
    var type: SourceType { get }
    /// True while the source is still reading (a big playlist): the catalogue refreshes as more arrives.
    var isStreaming: Bool { get }
    func liveCategories() async throws -> [XCategory]
    func vodCategories() async throws -> [XCategory]
    func seriesCategories() async throws -> [XCategory]
    /// nil = every channel of the source.
    func liveStreams(category: String?) async throws -> [XLive]
    func vodStreams(category: String?) async throws -> [XVod]
    func seriesList(category: String?) async throws -> [XSeries]
    /// get_vod_info / get_series_info shaped answer.
    func info(film: Bool, id: String) async throws -> [String: Any]
    /// The address VLC plays. A portal answers with a placeholder that VLCController resolves at play time.
    func streamURL(kind: ItemKind, id: String, ext: String) -> URL?
}

extension LibrarySource {
    var isStreaming: Bool { false }
}

// Records the app builds without a JSON decode.
extension XLive {
    init(id: String, name: String, icon: String, categoryId: String) {
        self.id = id; self.name = name; self.icon = icon; self.categoryId = categoryId; self.adult = false
    }
}
extension XVod {
    init(id: String, name: String, icon: String, categoryId: String, ext: String) {
        self.id = id; self.name = name; self.icon = icon; self.categoryId = categoryId; self.ext = ext; self.adult = false
    }
}
extension XSeries {
    init(id: String, name: String, cover: String, categoryId: String) {
        self.id = id; self.name = name; self.cover = cover; self.categoryId = categoryId
        plot = ""; genre = ""; year = ""; rating = ""; backdrops = []; adult = false
    }
}

/// What the player sends for one stream (a playlist can name a user agent and a referrer per channel).
struct StreamHeaders: Equatable, Sendable {
    var userAgent = ""
    var referrer = ""
    var isEmpty: Bool { userAgent.isEmpty && referrer.isEmpty }
}

/// Stream address -> headers, filled by the M3U adapter, read by VLCController.
final class StreamHeaderRegistry: @unchecked Sendable {
    static let shared = StreamHeaderRegistry()
    private let lock = NSLock()
    private var map: [String: StreamHeaders] = [:]
    func set(_ url: String, _ h: StreamHeaders) { lock.lock(); map[url] = h; lock.unlock() }
    func headers(for url: String) -> StreamHeaders? { lock.lock(); defer { lock.unlock() }; return map[url] }
    func clear() { lock.lock(); map = [:]; lock.unlock() }
}
