import Foundation

/// The library an M3U playlist builds: the same records the Xtream panel answers with, grouped by playlist group.
final class M3UStore: @unchecked Sendable {
    struct Bucket<T> {
        var order: [String] = []
        var by: [String: [T]] = [:]
        mutating func add(_ g: String, _ v: T) {
            if by[g] == nil { by[g] = []; order.append(g) }
            by[g]?.append(v)
        }
        var categories: [XCategory] { order.map { XCategory(id: $0, name: $0) } }
        mutating func retain(_ keep: Set<String>) {
            order = order.filter { keep.contains($0) }
            by = by.filter { keep.contains($0.key) }
        }
        var count: Int { by.values.reduce(0) { $0 + $1.count } }
    }
    private let lock = NSLock()
    private var _live = Bucket<XLive>(), _vod = Bucket<XVod>(), _series = Bucket<XSeries>()
    private var _episodes: [String: [String: [Episode]]] = [:]
    private var _guide = ""

    func with<R>(_ f: (M3UStore) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(self) }
    var live: Bucket<XLive> { get { lock.lock(); defer { lock.unlock() }; return _live } set { lock.lock(); _live = newValue; lock.unlock() } }
    var vod: Bucket<XVod> { get { lock.lock(); defer { lock.unlock() }; return _vod } set { lock.lock(); _vod = newValue; lock.unlock() } }
    var series: Bucket<XSeries> { get { lock.lock(); defer { lock.unlock() }; return _series } set { lock.lock(); _series = newValue; lock.unlock() } }
    var guide: String { get { lock.lock(); defer { lock.unlock() }; return _guide } set { lock.lock(); _guide = newValue; lock.unlock() } }
    func episodes(of id: String) -> [String: [Episode]] { lock.lock(); defer { lock.unlock() }; return _episodes[id] ?? [:] }

    func addLive(_ g: String, _ v: XLive) { lock.lock(); _live.add(g, v); lock.unlock() }
    func addVod(_ g: String, _ v: XVod) { lock.lock(); _vod.add(g, v); lock.unlock() }
    func addSeries(_ g: String, _ v: XSeries) { lock.lock(); _series.add(g, v); lock.unlock() }
    func hasSeries(_ g: String, _ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return _series.by[g]?.contains { $0.id == id } ?? false }
    func addEpisode(series: String, season: String, _ e: Episode) { lock.lock(); _episodes[series, default: [:]][season, default: []].append(e); lock.unlock() }
    func retain(_ keep: Set<String>) { lock.lock(); _live.retain(keep); _vod.retain(keep); _series.retain(keep); lock.unlock() }
    var entryCount: Int { lock.lock(); defer { lock.unlock() }; return _live.count + _vod.count + _series.count }
    func reset() { lock.lock(); _live = .init(); _vod = .init(); _series = .init(); _episodes = [:]; _guide = ""; lock.unlock() }
}

/// An M3U playlist read line by line. Bytes go in as they arrive; only whole lines are parsed, so a huge file never sits in memory.
/// mode .all keeps every entry · .index only counts entries per group · .filter keeps the entries of the ticked groups.
final class M3UParser {
    enum Mode { case all, index, filter }
    enum Kind { case live, film, series }
    struct GroupInfo { var n = 0; var dropped = 0; var kind = Kind.live }

    let store: M3UStore
    var mode: Mode = .all
    var keep: Set<String> = []
    var capKept = 60_000
    private(set) var idx: [String: GroupInfo] = [:]
    private(set) var order: [String] = []
    private(set) var kept = 0
    private(set) var capped = false
    private(set) var entries = 0
    private(set) var orphans = 0
    private(set) var comments = 0
    private var pending: Pending?
    private var carry = Data()
    private var first = true

    struct Pending {
        var name = "", tvgName = "", logo = "", group = "", tvgId = "", ua = "", ref = ""
    }

    init(store: M3UStore = M3UStore()) { self.store = store }

    // MARK: bytes in

    func feed(_ data: Data, last: Bool) {
        carry.append(data)
        var cut = carry.count
        if !last {
            guard let nl = carry.lastIndex(of: 10) else { return }
            cut = carry.distance(from: carry.startIndex, to: nl) + 1
        }
        let head = carry.prefix(cut)
        var text = String(decoding: head, as: UTF8.self)
        carry = Data(carry.dropFirst(cut))        // a copy: the big chunk can go
        if first { first = false; if text.hasPrefix("\u{FEFF}") { text.removeFirst() } }
        text.enumerateLines { line, _ in self.line(line) }
    }

    func parse(_ text: String) {
        feed(Data(text.utf8), last: true)
    }

    // MARK: one line

    private static let attrRE = try! NSRegularExpression(pattern: "([A-Za-z0-9_-]+)=\"([^\"]*)\"")
    static func attrs(_ line: String) -> [String: String] {
        var o: [String: String] = [:]
        let ns = line as NSString
        for m in attrRE.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            o[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return o
    }

    private static let filmExt = try! NSRegularExpression(pattern: "\\.(mp4|mkv|avi|mov|m4v)(\\?.*)?$", options: .caseInsensitive)
    private static let liveExt = try! NSRegularExpression(pattern: "\\.(m3u8|ts)(\\?.*)?$", options: .caseInsensitive)
    private static let filmGroup = try! NSRegularExpression(pattern: "(^|[\\s|:/\\-])(movies?|films?|vod|cin[eé]ma)([\\s|:/\\-]|$)", options: .caseInsensitive)
    private static let seriesGroup = try! NSRegularExpression(pattern: "(^|[\\s|:/\\-])(series|s[eé]ries|tv ?shows?|shows)([\\s|:/\\-]|$)", options: .caseInsensitive)
    private static let episodeName = try! NSRegularExpression(pattern: "^(.*?)[\\s._-]*S(\\d{1,2})\\s?E(\\d{1,3})\\b[\\s._:-]*(.*)$", options: .caseInsensitive)
    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil }

    static func ext(of url: String) -> String {
        guard let m = filmExt.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) else { return "mp4" }
        return (url as NSString).substring(with: m.range(at: 1)).lowercased()
    }

    func line(_ raw: String) {
        var l = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return }
        if l.hasPrefix("#EXTM3U") {
            let h = Self.attrs(l)
            let g = h["url-tvg"] ?? h["x-tvg-url"] ?? h["tvg-url"] ?? ""
            store.guide = (g.split(separator: ",").first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
            return
        }
        if l.hasPrefix("#EXTINF") {
            let a = Self.attrs(l)
            var name = ""
            let from = l.range(of: "\"", options: .backwards)?.upperBound ?? l.startIndex
            if let c = l[from...].firstIndex(of: ",") { name = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces) }
            pending = Pending(name: name, tvgName: a["tvg-name"] ?? "", logo: a["tvg-logo"] ?? "", group: a["group-title"] ?? "", tvgId: a["tvg-id"] ?? "",
                              ua: a["http-user-agent"] ?? "", ref: a["http-referrer"] ?? a["http-referer"] ?? "")
            return
        }
        if l.hasPrefix("#EXTGRP:") {
            if pending != nil, pending!.group.isEmpty { pending!.group = String(l.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            return
        }
        if l.hasPrefix("#EXTVLCOPT:") {
            let kv = l.dropFirst(11)
            if pending != nil, let eq = kv.firstIndex(of: "="), eq != kv.startIndex {
                let k = kv[..<eq].lowercased(), v = kv[kv.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if k == "http-user-agent" { pending!.ua = v } else if k == "http-referrer" || k == "http-referer" { pending!.ref = v }
            }
            return
        }
        if l.hasPrefix("#") { comments += 1; return }
        guard var info = pending else { orphans += 1; return }
        // Kodi style headers after the address: url|User-Agent=..&Referer=..
        if let bar = l.firstIndex(of: "|"), bar != l.startIndex, l.lowercased().hasPrefix("http") {
            let hs = l[l.index(after: bar)...].split(separator: "&")
            l = String(l[..<bar])
            for h in hs {
                guard let e = h.firstIndex(of: "=") else { continue }
                let k = h[..<e].lowercased()
                let rawV = String(h[h.index(after: e)...])
                let v = rawV.removingPercentEncoding ?? rawV
                if k == "user-agent" { info.ua = v } else if k == "referer" || k == "referrer" { info.ref = v }
            }
        }
        pending = nil
        add(url: l, info: info)
    }

    // MARK: classify and keep

    private func add(url: String, info: Pending) {
        let groups = (info.group.isEmpty ? "Other" : info.group).split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.map { $0.isEmpty ? "Other" : $0 }
        let name = info.name.isEmpty ? (info.tvgName.isEmpty ? url : info.tvgName) : info.name
        let isLive = Self.matches(Self.liveExt, url)
        let byExt = Self.matches(Self.filmExt, url)
        var any = false
        var seen = Set<String>()
        for g in groups where seen.insert(g).inserted {
            var kind = Kind.live
            var epi: (title: String, season: String, num: Int, rest: String)?
            if byExt { kind = .film }
            else if !isLive, Self.matches(Self.filmGroup, g) { kind = .film }
            if Self.matches(Self.seriesGroup, g), byExt || !isLive {
                let ns = name as NSString
                if let m = Self.episodeName.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) {
                    let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        kind = .series
                        epi = (title, String(Int(ns.substring(with: m.range(at: 2))) ?? 1), Int(ns.substring(with: m.range(at: 3))) ?? 0, ns.substring(with: m.range(at: 4)))
                    }
                }
            }
            var ix: GroupInfo
            if let known = idx[g] { ix = known } else { order.append(g); ix = GroupInfo(kind: kind) }
            ix.n += 1
            let keepIt = mode == .all || (mode == .filter && keep.contains(g) && kept < capKept)
            if !keepIt {
                ix.dropped += 1
                if mode == .filter, keep.contains(g) { capped = true }
                idx[g] = ix
                continue
            }
            idx[g] = ix
            switch kind {
            case .live: self.store.addLive(g, XLive(id: url, name: name, icon: info.logo, categoryId: g))
            case .film: self.store.addVod(g, XVod(id: url, name: name, icon: info.logo, categoryId: g, ext: Self.ext(of: url)))
            case .series:
                if let e = epi {
                    let sid = "s:" + e.title.lowercased()
                    if !self.store.hasSeries(g, sid) { self.store.addSeries(g, XSeries(id: sid, name: e.title, cover: info.logo, categoryId: g)) }
                    self.store.addEpisode(series: sid, season: e.season, Episode(id: url, num: e.num, title: e.rest.isEmpty ? "Episode \(e.num)" : e.rest, ext: Self.ext(of: url), still: info.logo, durationSecs: 0))
                }
            }
            kept += 1
            any = true
        }
        if any {
            entries += 1
            if !info.ua.isEmpty || !info.ref.isEmpty { StreamHeaderRegistry.shared.set(url, StreamHeaders(userAgent: info.ua, referrer: info.ref)) }
        }
    }

    /// Switch to .filter: entries already held for groups that are not ticked go away.
    func setKeep(_ keep: Set<String>) {
        self.keep = keep; mode = .filter
        store.retain(keep)
        kept = store.entryCount
        for g in order where !keep.contains(g) { if var x = idx[g] { x.dropped = x.n; idx[g] = x } }
    }
    /// Entries a ticked group lost while the playlist was only counted: a second read is needed.
    func needsSecondRead(for keep: Set<String>) -> Bool { keep.contains { (idx[$0]?.dropped ?? 0) > 0 } }
    var groupCounts: [(name: String, n: Int)] { order.map { ($0, idx[$0]?.n ?? 0) } }
}

/// An Xtream export link (.../get.php?username=U&password=P, any order, any extra parameters) is not downloaded:
/// its server and login go through the Xtream adapter, which gives the full library.
struct XtreamLink: Equatable {
    let base: String, user: String, pass: String
    static func parse(_ raw: String) -> XtreamLink? {
        var u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return nil }
        if u.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil { u = "http://" + u }
        guard let comps = URLComponents(string: u), let host = comps.host, comps.path.lowercased().hasSuffix("get.php") else { return nil }
        var q: [String: String] = [:]
        for it in comps.queryItems ?? [] { q[it.name.lowercased()] = it.value ?? "" }
        guard let user = q["username"], !user.isEmpty, let pass = q["password"], !pass.isEmpty else { return nil }
        let base = (comps.scheme ?? "http") + "://" + host + (comps.port.map { ":\($0)" } ?? "")
        return XtreamLink(base: base, user: user, pass: pass)
    }
}
