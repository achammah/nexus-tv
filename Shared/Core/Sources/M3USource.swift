import Foundation

/// What the group picker shows while a big playlist downloads.
struct PickerState: Sendable {
    var read = 0, total = 0
    var groups: [(name: String, n: Int)] = []
    var done = false
    var kept = 0
    var reading = false        // the second read with the choice
}

/// An M3U playlist (link, optional guide link, name). The download streams: the first part shows at once and the
/// rest arrives while the owner browses. Over `limitBytes` the entries are only counted per group until the owner
/// picks which groups to keep (`keepGroups`).
final class M3USource: NSObject, LibrarySource, URLSessionDataDelegate, @unchecked Sendable {
    var type: SourceType { .m3u }
    let url: URL
    let epgLink: String
    /// Up to this many bytes everything is kept; beyond it the group picker asks.
    let limitBytes: Int
    let store = M3UStore()
    private(set) var parser: M3UParser
    private let capKept: Int
    private let forcePicker: Bool
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q }()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 3600
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (AppleTV) NexusTV/1.0"]
        return URLSession(configuration: c, delegate: self, delegateQueue: queue)
    }()
    private var task: URLSessionDataTask?
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var failure: SourceError?
    private var _done = false, _picking = false, _firstSeen = false, _reading = false
    private var bytesRead = 0, total = 0
    private var gotHead = false
    private var streamFinished = false          // the download ended (a pick can still be pending)
    private var keptGroups: Set<String>?

    /// Called on a background queue as entries arrive and when the download ends.
    var onChange: (@Sendable () -> Void)?
    /// Called when the playlist is over the limit and the owner must choose groups; again for each progress step.
    var onPicker: (@Sendable (PickerState) -> Void)?

    init(url: URL, epg: String = "", keptGroups: [String]? = nil, limitBytes: Int = 8 * 1024 * 1024, capKept: Int = M3USource.defaultCap, forcePicker: Bool = false) {
        self.url = url; self.epgLink = epg; self.limitBytes = limitBytes; self.capKept = capKept; self.forcePicker = forcePicker
        parser = M3UParser(store: store)
        parser.capKept = capKept
        super.init()
        if let k = keptGroups, !k.isEmpty { self.keptGroups = Set(k); parser.mode = .filter; parser.keep = Set(k) }
        else if forcePicker { parser.mode = .index; _picking = true }
    }

    /// tvOS keeps at most 60,000 entries; the Mac has room for more.
    static var defaultCap: Int {
        #if os(tvOS)
        return 60_000
        #else
        return 250_000
        #endif
    }

    var guideURL: String { store.guide.isEmpty ? epgLink : store.guide }
    var isStreaming: Bool { lock.lock(); defer { lock.unlock() }; return !_done && failure == nil }
    var isPicking: Bool { lock.lock(); defer { lock.unlock() }; return _picking }
    var capped: Bool { parser.capped }
    var groupCount: Int { parser.order.count }

    // MARK: running

    func start() {
        lock.lock()
        _done = false; failure = nil; gotHead = false; bytesRead = 0; streamFinished = false
        lock.unlock()
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        task = session.dataTask(with: req)
        task?.resume()
    }
    func cancel() { task?.cancel(); session.invalidateAndCancel(); finish(error: .cancelled) }

    /// Returns once the first entries are in, or throws why the playlist cannot be read.
    func waitForFirst() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let f = failure { lock.unlock(); c.resume(throwing: f); return }
            if _firstSeen || _done { lock.unlock(); c.resume(); return }
            waiters.append(c); lock.unlock()
        }
    }

    private func resumeWaiters(_ error: SourceError?) {
        lock.lock(); let w = waiters; waiters = []; lock.unlock()
        for c in w { if let error { c.resume(throwing: error) } else { c.resume() } }
    }

    private func finish(error: SourceError?) {
        lock.lock()
        if let error { failure = failure ?? error } else { _done = true }
        let first = _firstSeen
        lock.unlock()
        // a playlist that ends without one entry is not a playlist
        if error == nil, !first, store.entryCount == 0 { lock.lock(); failure = .notAPlaylist; lock.unlock(); resumeWaiters(.notAPlaylist) }
        else { resumeWaiters(error) }
        onChange?()
    }

    func pickerState() -> PickerState {
        lock.lock(); defer { lock.unlock() }
        return PickerState(read: bytesRead, total: total, groups: parser.groupCounts, done: streamFinished, kept: parser.kept, reading: _reading)
    }

    // MARK: URLSessionDataDelegate (runs on `queue`, one at a time)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let h = response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            completionHandler(.cancel)
            finish(error: h.statusCode == 401 || h.statusCode == 403 ? .refused : .unreachable)
            return
        }
        lock.lock(); total = max(0, Int(response.expectedContentLength)); lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let head = !gotHead
        gotHead = true
        bytesRead += data.count
        lock.unlock()
        if head {
            let s = String(decoding: data.prefix(4000), as: UTF8.self)
            if !s.contains("#EXTM3U") && !s.contains("#EXTINF") { dataTask.cancel(); finish(error: .notAPlaylist); return }
        }
        parser.feed(data, last: false)
        lock.lock()
        if parser.mode == .all, bytesRead >= limitBytes { parser.mode = .index; _picking = true }
        let picking = _picking
        if !_firstSeen, parser.entries > 0 { _firstSeen = true; lock.unlock(); resumeWaiters(nil) } else { lock.unlock() }
        onChange?()
        if picking { onPicker?(pickerState()) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error as NSError? {
            if e.code == NSURLErrorCancelled { return }
            finish(error: .unreachable); return
        }
        parser.feed(Data(), last: true)
        lock.lock(); streamFinished = true; let picking = _picking; lock.unlock()
        if picking { onPicker?(pickerState()); onChange?(); return }       // everything is counted: wait for the choice
        if parser.mode != .filter, parser.idx.isEmpty { finish(error: .notAPlaylist); return }      // no entry at all: not a playlist
        lock.lock(); _firstSeen = true; lock.unlock()
        finish(error: nil)
    }

    // MARK: the choice

    /// The owner ticked these groups. When a ticked group already lost entries while only counting, the playlist is read again.
    func keepGroups(_ set: Set<String>) {
        lock.lock(); keptGroups = set; _picking = false
        let again = parser.needsSecondRead(for: set)
        let finished = streamFinished
        lock.unlock()
        if again {
            task?.cancel()
            store.reset()
            let p = M3UParser(store: store); p.capKept = capKept; p.mode = .filter; p.keep = set
            parser = p
            lock.lock(); _reading = true; _firstSeen = false; lock.unlock()
            start()
            return
        }
        parser.setKeep(set)
        if finished { lock.lock(); _done = true; lock.unlock(); onChange?() }
    }
    /// The groups chosen, to save with the source.
    var chosenGroups: [String]? { lock.lock(); defer { lock.unlock() }; return keptGroups.map { $0.sorted() } }

    // MARK: LibrarySource

    func liveCategories() async throws -> [XCategory] { try await waitForFirst(); return store.live.categories }
    func vodCategories() async throws -> [XCategory] { try await waitForFirst(); return store.vod.categories }
    func seriesCategories() async throws -> [XCategory] { try await waitForFirst(); return store.series.categories }
    func liveStreams(category: String?) async throws -> [XLive] {
        let b = store.live
        if let c = category { return b.by[c] ?? [] }
        return b.order.flatMap { b.by[$0] ?? [] }
    }
    func vodStreams(category: String?) async throws -> [XVod] {
        let b = store.vod
        if let c = category { return b.by[c] ?? [] }
        return b.order.flatMap { b.by[$0] ?? [] }
    }
    func seriesList(category: String?) async throws -> [XSeries] {
        let b = store.series
        if let c = category { return b.by[c] ?? [] }
        return b.order.flatMap { b.by[$0] ?? [] }
    }
    func info(film: Bool, id: String) async throws -> [String: Any] {
        if film { return ["info": [String: Any](), "movie_data": ["container_extension": M3UParser.ext(of: id)]] }
        let eps = store.episodes(of: id)
        var out: [String: Any] = [:]
        for (season, list) in eps {
            out[season] = list.sorted { $0.num < $1.num }.map { e -> [String: Any] in
                ["id": e.id, "episode_num": e.num, "title": e.title, "container_extension": e.ext, "season": season, "info": ["movie_image": e.still]]
            }
        }
        return ["info": ["name": id.hasPrefix("s:") ? String(id.dropFirst(2)).capitalized : id], "episodes": out]
    }
    func streamURL(kind: ItemKind, id: String, ext: String) -> URL? { URL(string: id) }
}
