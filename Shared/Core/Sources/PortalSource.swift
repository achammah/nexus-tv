import Foundation

/// A Stalker / MAG portal. The MAC address is the login: it goes out as the cookie mac=..., the way a set-top box sends it.
/// Call order: handshake (token) → get_profile → genres / channels (itv) · vod and series categories and pages · create_link per stream.
final class PortalSource: LibrarySource, @unchecked Sendable {
    var type: SourceType { .portal }
    let base: String
    let mac: String
    /// The portal of the active source, for the player (VLCController resolves a portal placeholder address here).
    static var current: PortalSource?

    /// Test seam: how a request is answered (nil = the network).
    var transport: (@Sendable (URLRequest) async throws -> Data)?

    private let lock = NSLock()
    private var token = ""
    private var ready = false
    private var genres: [XCategory]?
    private var channelsCache: [[String: Any]]?
    private var vodCats: [XCategory]?
    private var seriesCats: [XCategory]?
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        return URLSession(configuration: c)
    }()

    init(base: String, mac: String) {
        var u = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        if !u.isEmpty && !u.contains("://") { u = "http://" + u }
        self.base = u
        self.mac = mac.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// 00:1A:79:xx:xx:xx. Any MAC is accepted by the format check; portals refuse unknown ones at the handshake.
    static func validMAC(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).range(of: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil
    }

    var endpoint: String {
        var u = base
        if u.hasSuffix("/c") { u.removeLast(2) }
        while u.hasSuffix("/") { u.removeLast() }
        return u.contains("stalker_portal") ? u + "/server/load.php" : u + "/portal.php"
    }

    // MARK: calls

    func call(_ query: String) async throws -> Any {
        guard let url = URL(string: endpoint + "?" + query + "&JsHttpRequest=1-xml") else { throw SourceError.unreachable }
        var req = URLRequest(url: url)
        req.httpShouldHandleCookies = false
        req.setValue("mac=\(mac); stb_lang=en; timezone=Europe/Paris", forHTTPHeaderField: "Cookie")
        req.setValue("Model: MAG250; Link: WiFi", forHTTPHeaderField: "X-User-Agent")
        req.setValue("Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3", forHTTPHeaderField: "User-Agent")
        lock.lock(); let t = token; lock.unlock()
        if !t.isEmpty { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        let data: Data
        if let transport { data = try await transport(req) }
        else {
            do {
                let (d, r) = try await session.data(for: req)
                if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw SourceError.refused }
                data = d
            } catch let e as SourceError { throw e } catch { throw SourceError.unreachable }
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw SourceError.refused }
        if let d = obj as? [String: Any], let js = d["js"] { return js }
        return obj
    }

    func ensure() async throws {
        lock.lock(); if ready { lock.unlock(); return }; lock.unlock()
        let hs = try await call("type=stb&action=handshake&token=&prehash=0")
        guard let tok = (hs as? [String: Any])?["token"] as? String, !tok.isEmpty else { throw SourceError.refused }
        lock.lock(); token = tok; lock.unlock()
        let prof = try await call("type=stb&action=get_profile&hd=1&auth_second_step=0&client_type=STB&api_signature=263")
        guard prof is [String: Any] else { lock.lock(); token = ""; lock.unlock(); throw SourceError.refused }
        lock.lock(); ready = true; lock.unlock()
    }

    private func cats(_ js: Any) -> [XCategory] {
        ((js as? [[String: Any]]) ?? []).compactMap { c in
            let id = "\(c["id"] ?? "")"
            guard !id.isEmpty, id != "*" else { return nil }
            return XCategory(id: id, name: (c["title"] as? String) ?? (c["name"] as? String) ?? id)
        }
    }
    private func logo(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        if s.hasPrefix("http") { return s }
        var origin = ""
        if let c = URLComponents(string: base), let host = c.host {
            origin = (c.scheme ?? "http") + "://" + host
            if let port = c.port { origin += ":" + String(port) }
        }
        return origin + (s.hasPrefix("/") ? "" : "/stalker_portal/misc/logos/320/") + s
    }

    // MARK: LibrarySource

    func liveCategories() async throws -> [XCategory] {
        try await ensure()
        if let g = genres { return g }
        var g = cats(try await call("type=itv&action=get_genres"))
        if g.isEmpty { g = [XCategory(id: "*", name: "All")] }
        genres = g
        return g
    }
    func vodCategories() async throws -> [XCategory] {
        try await ensure()
        if let c = vodCats { return c }
        let c = cats(try await call("type=vod&action=get_categories")); vodCats = c; return c
    }
    func seriesCategories() async throws -> [XCategory] {
        try await ensure()
        if let c = seriesCats { return c }
        let c = cats(try await call("type=series&action=get_categories")); seriesCats = c; return c
    }
    private func allChannels() async throws -> [[String: Any]] {
        try await ensure()
        if let c = channelsCache { return c }
        let js = try await call("type=itv&action=get_all_channels")
        let list = ((js as? [String: Any])?["data"] as? [[String: Any]]) ?? (js as? [[String: Any]]) ?? []
        channelsCache = list
        return list
    }
    func liveStreams(category: String?) async throws -> [XLive] {
        let all = try await allChannels()
        return all.compactMap { c in
            let genre = "\(c["tv_genre_id"] ?? "")"
            if let category, category != "*", genre != category { return nil }
            guard let cmd = c["cmd"] as? String else { return nil }
            return XLive(id: cmd, name: (c["name"] as? String) ?? cmd, icon: logo(c["logo"] as? String), categoryId: category ?? genre)
        }
    }
    /// The portal pages its lists; a few pages fill a shelf.
    private func pages(_ type: String, _ category: String?, maxPages: Int = 4) async throws -> [[String: Any]] {
        try await ensure()
        var out: [[String: Any]] = []
        var page = 1
        let cat = category.map { "&category=" + (Self.enc($0)) } ?? ""
        while page <= maxPages {
            let js: Any
            do { js = try await call("type=\(type)&action=get_ordered_list\(cat)&p=\(page)&sortby=added") }
            catch { if out.isEmpty { throw error } else { break } }
            let d = js as? [String: Any]
            let data = (d?["data"] as? [[String: Any]]) ?? []
            let totalItems = Int("\(d?["total_items"] ?? 0)") ?? 0
            let per = Int("\(d?["max_page_items"] ?? 0)") ?? (data.isEmpty ? 1 : data.count)
            out += data
            if data.isEmpty || page * max(1, per) >= totalItems { break }
            page += 1
        }
        return out
    }
    func vodStreams(category: String?) async throws -> [XVod] {
        try await pages("vod", category).map { v in
            let id = (v["cmd"] as? String) ?? "/media/\(v["id"] ?? "").mpg"
            return XVod(id: id, name: (v["name"] as? String) ?? id, icon: logo(v["screenshot_uri"] as? String), categoryId: category ?? "", ext: "mp4")
        }
    }
    func seriesList(category: String?) async throws -> [XSeries] {
        try await pages("series", category).map { v in
            XSeries(id: "\(v["id"] ?? "")", name: (v["name"] as? String) ?? "", cover: logo(v["screenshot_uri"] as? String), categoryId: category ?? "")
        }
    }
    func info(film: Bool, id: String) async throws -> [String: Any] {
        if film { return ["info": [String: Any](), "movie_data": ["container_extension": "mp4"]] }
        // seasons of a series: each entry lists its episode numbers; an episode plays through create_link with `series=<number>`
        try await ensure()
        let js = try await call("type=series&action=get_ordered_list&movie_id=\(Self.enc(id))&season_id=0&episode_id=0&p=1")
        let seasons = ((js as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        var out: [String: Any] = [:]
        for (i, s) in seasons.enumerated() {
            let cmd = (s["cmd"] as? String) ?? ""
            let nums = ((s["series"] as? [Any]) ?? []).compactMap { Int("\($0)") }
            out[String(i + 1)] = nums.map { n -> [String: Any] in
                ["id": cmd + "#" + String(n), "episode_num": n, "title": "Episode \(n)", "container_extension": "mp4", "season": String(i + 1), "info": ["movie_image": ""]]
            }
        }
        return ["info": ["name": ""], "episodes": out]
    }
    func streamURL(kind: ItemKind, id: String, ext: String) -> URL? {
        let k = kind == .live ? "itv" : kind == .film ? "vod" : "series"
        return PortalSource.placeholder(k, id)
    }

    // MARK: play address

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
    static func placeholder(_ kind: String, _ cmd: String) -> URL? {
        let b64 = Data(cmd.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "nxportal://\(kind)/\(b64)")
    }
    static func decode(_ url: URL) -> (kind: String, cmd: String)? {
        guard url.scheme == "nxportal", let kind = url.host else { return nil }
        var b = String(url.path.dropFirst()).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let cmd = String(data: d, encoding: .utf8) else { return nil }
        return (kind, cmd)
    }
    /// create_link turns the stored command into a stream URL. nil when the portal refuses.
    func resolve(_ placeholder: URL) async -> URL? {
        guard let p = Self.decode(placeholder) else { return placeholder }
        do {
            try await ensure()
            var cmd = p.cmd, series = ""
            if p.kind == "series", let h = cmd.lastIndex(of: "#") { series = String(cmd[cmd.index(after: h)...]); cmd = String(cmd[..<h]) }
            let js = try await call("type=\(p.kind == "series" ? "vod" : p.kind)&action=create_link&cmd=\(Self.enc(cmd))&series=\(series)&forced_storage=undefined&disable_ad=0&download=0")
            guard var u = (js as? [String: Any])?["cmd"] as? String else { return nil }
            if let r = u.range(of: "^\\S+\\s+(?=https?://)", options: .regularExpression) { u.removeSubrange(r) }
            return u.hasPrefix("http") ? URL(string: u) : nil
        } catch { return nil }
    }
}
