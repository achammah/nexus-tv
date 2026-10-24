import Foundation
import CoreGraphics

/// Finds a logo for a live channel, in this order:
///  a. the channel's own logo URL, when it loads;
///  b. the logo of a twin: another channel of the same source with the same cleaned name (FHD / HD / LQ copies);
///  c. the bundled map (Resources/channel-logos.json): cleaned name -> logo, from the Frame app's finished logo
///     pass (twins, iptv-org, jaruba, tv-logos, picons, Logopedia, TheSportsDB, Wikipedia; exact names only);
///  d. iptv-org (public): exact cleaned-name or alternative-name match only, same country preferred, widest logo;
///  e. none: the caller draws the wordmark tile.
/// A wrong logo is worse than none, so (c) never guesses.
enum LogoName {
    static let qualityWords: Set<String> = ["FHD", "UHD", "HD", "SD", "HEVC", "4K", "LQ", "RAW", "VIP"]
    private static let badgeOrder = ["4K", "UHD", "FHD", "HEVC", "HD", "LQ"]

    struct Parts: Equatable {
        /// Readable name without country prefix, brackets and quality words: "AFC Champions League 3".
        var name: String
        /// The first quality word among 4K/UHD/FHD/HEVC/HD/LQ (UHD shows as 4K), else nil.
        var quality: String?
        /// Two-letter country from a "BE|" or "US:" prefix, else nil.
        var country: String?
        /// Lower-case letters and digits only, accents folded: the key twins and iptv-org match on.
        var key: String
    }

    private static let prefix = try! NSRegularExpression(pattern: "^\\s*(?:\\|\\s*)?([A-Za-z]{2,4})\\s*(?:\\||:)\\s*(?:\\|\\s*)?")
    private static let brackets = try! NSRegularExpression(pattern: "\\([^)]*\\)|\\[[^\\]]*\\]")
    private static let ccAlias = ["UK": "GB", "ENF": "FR", "USA": "US"]

    static func parse(_ raw: String) -> Parts {
        var s = Clean.stripDecor(raw)
        var country: String? = nil
        // brackets may hold the quality ("(FHD)"): read it before they go
        var quality: String? = nil
        func scanQuality(_ t: String) {
            guard quality == nil else { return }
            let words = Set(t.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            if let q = badgeOrder.first(where: { words.contains($0) }) { quality = q == "UHD" ? "4K" : q }
        }
        if let m = prefix.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) {
            let tag = String(s[r]).uppercased()
            if tag.count == 2 { country = ccAlias[tag] ?? tag } else if let a = ccAlias[tag] { country = a }
            s = String(s[Range(m.range, in: s)!.upperBound...])
        }
        scanQuality(s)
        s = brackets.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        let kept = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !qualityWords.contains($0.uppercased()) }
        let name = kept.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -_|:"))
        return Parts(name: name, quality: quality, country: country, key: key(name))
    }

    static func key(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
    }

    /// "Belgium · Algemeen" -> "BE"
    static func country(fromSub sub: String) -> String? {
        let first = sub.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else { return nil }
        if first.count == 2 { return ccAlias[first.uppercased()] ?? first.uppercased() }
        return regionNames[first.lowercased()]
    }
    private static let regionNames: [String: String] = {
        var d: [String: String] = ["usa": "US", "uk": "GB", "united kingdom": "GB", "america": "US"]
        let en = Locale(identifier: "en_US")
        for code in Locale.Region.isoRegions.map(\.identifier) where code.count == 2 {
            if let n = en.localizedString(forRegionCode: code) { d[n.lowercased()] = code }
        }
        return d
    }()
}

/// iptv-org data reduced to what matching needs. Built from the two public JSON files.
struct IptvOrgIndex {
    struct Entry { var channel: String; var country: String }
    private(set) var byName: [String: [Entry]] = [:]
    private(set) var logo: [String: (url: String, width: Int)] = [:]

    init() {}
    init(channelsJSON: Data, logosJSON: Data) {
        struct C: Decodable { let id: String; let name: String; let alt_names: [String]?; let country: String? }
        struct L: Decodable { let channel: String; let url: String; let width: Int? }
        if let cs = try? JSONDecoder().decode([C].self, from: channelsJSON) {
            for c in cs {
                let e = Entry(channel: c.id, country: (c.country ?? "").uppercased())
                var keys = Set([LogoName.parse(c.name).key]); for a in c.alt_names ?? [] { keys.insert(LogoName.parse(a).key) }
                for k in keys where !k.isEmpty { byName[k, default: []].append(e) }
            }
        }
        if let ls = try? JSONDecoder().decode([L].self, from: logosJSON) {
            for l in ls {
                let w = l.width ?? 0
                if let cur = logo[l.channel], cur.width >= w { continue }
                logo[l.channel] = (l.url, w)
            }
        }
    }

    /// The logo of the one channel that carries exactly this name. Several channels: the one of the same country;
    /// without a country hint, only when they are all the same channel. Otherwise none.
    func url(forKey key: String, country: String?) -> String? {
        guard let es = byName[key], !es.isEmpty else { return nil }
        var pool = es
        if let cc = country, !cc.isEmpty {
            let same = es.filter { $0.country == cc }
            if !same.isEmpty { pool = same }
        }
        let ids = Set(pool.map(\.channel))
        guard ids.count == 1, let id = ids.first else { return nil }       // several channels of that name: no guess
        return logo[id]?.url
    }
}

final class ChannelLogos: @unchecked Sendable {
    static let shared = ChannelLogos()
    private let lock = NSLock()
    private var twins: [String: String] = [:]
    private var twinsStamp = -1
    private var iptv: IptvOrgIndex?
    private var iptvLoading = false
    private let maxAge: TimeInterval = 7 * 86400
    /// Cleaned name -> logo URL, shipped with the app.
    private lazy var bundled: [String: String] = {
        guard let u = Bundle.main.url(forResource: "channel-logos", withExtension: "json"), let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }()
    func bundledURL(forKey key: String) -> String? { lock.lock(); defer { lock.unlock() }; return bundled[key] }

    /// Twin map: cleaned name -> a logo URL of a channel of that name. Built once per catalogue size, off the caller's thread.
    static func buildTwins(from index: [String: [Channel]]) -> [String: String] {
        var m: [String: String] = [:]
        for ch in index.values.joined() where !ch.icon.isEmpty && ch.icon.hasPrefix("http") {
            let k = LogoName.parse(ch.name).key
            if !k.isEmpty, m[k] == nil { m[k] = ch.icon }
        }
        return m
    }

    func ensureTwins(_ index: [String: [Channel]]) {
        let stamp = index.values.reduce(0) { $0 + $1.count }
        lock.lock(); let same = stamp == twinsStamp; if !same { twinsStamp = stamp }; lock.unlock()
        if same || index.isEmpty { return }
        let m = Self.buildTwins(from: index)
        lock.lock(); twins = m; lock.unlock()
    }
    func twin(forKey key: String, excluding icon: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let u = twins[key], u != icon else { return nil }
        return u
    }

    // MARK: iptv-org files

    private var folder: URL {
        var d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        d = d.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.nexus.tv").appendingPathComponent("iptv-org")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Loads the iptv-org index once; downloads the two files only when they are missing or older than a week.
    private func iptvIndex() async -> IptvOrgIndex? {
        lock.lock()
        if let i = iptv { lock.unlock(); return i }
        if iptvLoading { lock.unlock(); return nil }
        iptvLoading = true; lock.unlock()
        let idx: IptvOrgIndex? = await Task.detached(priority: .utility) { [folder, maxAge] () -> IptvOrgIndex? in
            let files = [("channels.json", "https://iptv-org.github.io/api/channels.json"), ("logos.json", "https://iptv-org.github.io/api/logos.json")]
            for (name, remote) in files {
                let f = folder.appendingPathComponent(name)
                let age = (try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate] as? Date).flatMap { $0 }.map { Date().timeIntervalSince($0) } ?? .infinity
                if age > maxAge, let u = URL(string: remote), let (d, r) = try? await URLSession.shared.data(from: u),
                   (r as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty { try? d.write(to: f, options: .atomic) }
            }
            guard let c = try? Data(contentsOf: folder.appendingPathComponent("channels.json")),
                  let l = try? Data(contentsOf: folder.appendingPathComponent("logos.json")) else { return nil }
            return IptvOrgIndex(channelsJSON: c, logosJSON: l)
        }.value
        lock.lock(); iptv = idx; iptvLoading = false; lock.unlock()
        return idx
    }

    /// Which logo address worked for a cleaned name, kept across launches so a tile shows at once next time.
    private var known: [String: String] = (UserDefaults.standard.dictionary(forKey: "nx.logoKnown") as? [String: String]) ?? [:]
    private var knownDirty = false
    private func remember(_ key: String, _ url: String) {
        lock.lock(); let changed = known[key] != url; if changed { known[key] = url; knownDirty = true }; lock.unlock()
        if changed { scheduleSave() }
    }
    private var saveQueued = false
    private func scheduleSave() {
        lock.lock(); let go = !saveQueued; saveQueued = true; lock.unlock()
        guard go else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [self] in
            lock.lock(); let snap = known; saveQueued = false; knownDirty = false; lock.unlock()
            UserDefaults.standard.set(snap, forKey: "nx.logoKnown")
        }
    }

    /// Steps a to d as pictures, all sources asked at once: the first one that answers in priority order wins,
    /// so a dead provider link no longer makes the tile wait for its timeout. nil = nothing found: draw the wordmark.
    func resolve(name: String, icon: String, sub: String, maxPixel: CGFloat) async -> CGImage? {
        let loader = ImageLoader.shared
        let p = LogoName.parse(name)
        lock.lock(); let hit = known[p.key]; lock.unlock()
        if let hit, let u = URL(string: hit), let i = await loader.image(u, maxPixel: maxPixel) { return i }
        var candidates: [String] = []
        if !icon.isEmpty { candidates.append(icon) }
        if let t = twin(forKey: p.key, excluding: icon) { candidates.append(t) }
        if let b = bundledURL(forKey: p.key), b != icon { candidates.append(b) }
        var seen = Set<String>(); candidates = candidates.filter { seen.insert($0).inserted }
        if !candidates.isEmpty {
            let found: (String, CGImage)? = await withTaskGroup(of: (Int, String, CGImage?).self) { g in
                for (i, c) in candidates.enumerated() {
                    g.addTask { let u = Img.url(c) ?? URL(string: c); return (i, c, u == nil ? nil : await loader.image(u!, maxPixel: maxPixel)) }
                }
                var best: (Int, String, CGImage)? = nil
                for await (i, c, img) in g {
                    guard let img else { continue }
                    if best == nil || i < best!.0 { best = (i, c, img) }
                    if i == 0 { break }                                   // the channel's own logo: nothing beats it
                }
                g.cancelAll()
                return best.map { ($0.1, $0.2) }
            }
            if let found { remember(p.key, found.0); return found.1 }
        }
        if p.key.count >= 3, let idx = await iptvIndex(), let s = idx.url(forKey: p.key, country: p.country ?? LogoName.country(fromSub: sub)),
           let u = URL(string: s), let i = await loader.image(u, maxPixel: maxPixel) { remember(p.key, s); return i }
        return nil
    }

    /// Warms the logos of the given channels in the background, a few at a time, so pages open with their tiles filled.
    func prefetch(_ channels: [Channel], maxPixel: CGFloat = 300) {
        let list = Array(channels.prefix(400))
        Task.detached(priority: .background) { [self] in
            await withTaskGroup(of: Void.self) { g in
                var running = 0
                for ch in list {
                    if running >= 6 { await g.next(); running -= 1 }
                    g.addTask { _ = await self.resolve(name: ch.name, icon: ch.icon, sub: "", maxPixel: maxPixel) }
                    running += 1
                }
            }
        }
    }
}
