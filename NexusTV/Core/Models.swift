import Foundation

// MARK: - Lenient JSON values (Xtream panels mix strings, numbers and nulls for the same field)

struct FlexString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else { value = "" }
    }
}

extension KeyedDecodingContainer {
    func flex(_ key: Key) -> String { ((try? decodeIfPresent(FlexString.self, forKey: key)) ?? nil)?.value ?? "" }
    func flexList(_ key: Key) -> [String] {
        if let a = try? decodeIfPresent([FlexString].self, forKey: key) { return a.map(\.value) }
        let s = flex(key)
        return s.isEmpty ? [] : [s]
    }
}

// MARK: - Provider records (only the fields the app uses)

struct XCategory: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case category_id, category_name }
    init(id: String, name: String) { self.id = id; self.name = name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flex(.category_id); name = c.flex(.category_name)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .category_id); try c.encode(name, forKey: .category_name)
    }
}

struct XLive: Decodable {
    let id: String, name: String, icon: String, categoryId: String, adult: Bool
    enum K: String, CodingKey { case stream_id, name, stream_icon, category_id, is_adult }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = c.flex(.stream_id); name = c.flex(.name); icon = c.flex(.stream_icon); categoryId = c.flex(.category_id)
        adult = c.flex(.is_adult) == "1"
    }
}

struct XVod: Decodable {
    let id: String, name: String, icon: String, categoryId: String, ext: String, adult: Bool
    enum K: String, CodingKey { case stream_id, name, stream_icon, category_id, container_extension, is_adult }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = c.flex(.stream_id); name = c.flex(.name); icon = c.flex(.stream_icon); categoryId = c.flex(.category_id)
        ext = c.flex(.container_extension); adult = c.flex(.is_adult) == "1"
    }
}

struct XSeries: Decodable {
    let id: String, name: String, cover: String, categoryId: String, plot: String, genre: String, year: String, rating: String
    let backdrops: [String]
    let adult: Bool
    enum K: String, CodingKey { case series_id, name, cover, category_id, plot, genre, releaseDate, release_date, rating, backdrop_path, is_adult }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = c.flex(.series_id); name = c.flex(.name); cover = c.flex(.cover); categoryId = c.flex(.category_id)
        plot = c.flex(.plot); genre = c.flex(.genre); rating = c.flex(.rating)
        let rd = c.flex(.releaseDate).isEmpty ? c.flex(.release_date) : c.flex(.releaseDate)
        year = String(rd.prefix(4))
        backdrops = c.flexList(.backdrop_path)
        adult = c.flex(.is_adult) == "1"
    }
}

// MARK: - App items

enum ItemKind: String, Codable, Sendable { case live, film, series, episode }

/// One thing the app can show on a tile, save to My List or resume.
struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    var kind: ItemKind
    var id: String
    var name: String
    var img: String = ""
    var ext: String = ""
    var sub: String = ""            // live: "Belgium · Algemeen"
    var seriesId: String? = nil     // episode: its series
    var seriesName: String? = nil
    var lang: String? = nil         // search results from another language: its tag, shown as a badge
    var key: String { kind.rawValue + ":" + id }
}

struct ResumePoint: Codable, Hashable {
    var item: MediaItem
    var posMs: Int
    var durMs: Int
    var at: Date
    var fraction: Double { durMs > 0 ? min(1, Double(posMs) / Double(durMs)) : 0 }
}

struct Channel: Codable, Hashable, Identifiable, Sendable {
    let id: String, name: String, icon: String, categoryId: String
}

/// A film or series as kept in the search index.
struct IndexEntry: Codable, Hashable, Sendable {
    let id: String, name: String, img: String, cat: String, ext: String
}

struct HeroItem: Hashable {
    let id: String, title: String, year: String, genre: String, rating: String, plot: String, backdrop: String, cover: String
}

/// Film / series details from get_vod_info and get_series_info.
struct Details {
    var name = ""
    var poster = ""
    var facts: [String] = []
    var plot = ""
    var backdrop = ""
    var ext = ""
    var seasons: [String] = []
    var episodes: [String: [Episode]] = [:]
}

struct Episode: Hashable, Identifiable {
    let id: String, num: Int, title: String, ext: String, still: String, durationSecs: Int
}

// MARK: - Text clean-up (same rules as the Frame app's build_data.py)

enum Clean {
    private static let superscripts = try! NSRegularExpression(pattern: "[\u{1D00}-\u{1DBF}\u{2070}-\u{209F}\u{02B0}-\u{02FF}]+")
    /// Compiled once per pattern (thread-safe cache): building a regex on every call was a measured hot spot.
    private static let reCache = NSCache<NSString, NSRegularExpression>()
    private static func re(_ pattern: String) -> NSRegularExpression? {
        if let r = reCache.object(forKey: pattern as NSString) { return r }
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        reCache.setObject(r, forKey: pattern as NSString)
        return r
    }
    private static func sub(_ s: String, _ pattern: String, _ with: String = "") -> String {
        guard let re = re(pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: with)
    }
    private static func group1(_ s: String, _ pattern: String) -> String? {
        guard let re = re(pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
    /// Results of the label clean-ups, kept: category names are drawn again on every screen refresh.
    private static let memo = NSCache<NSString, NSString>()
    private static func memo(_ kind: String, _ s: String, _ f: () -> String) -> String {
        let k = (kind + "\u{1}" + s) as NSString
        if let v = memo.object(forKey: k) { return v as String }
        let v = f(); memo.setObject(v as NSString, forKey: k); return v
    }
    private static func squash(_ s: String) -> String {
        sub(s, "\\s+", " ").trimmingCharacters(in: .whitespaces)
    }
    static func stripDecor(_ s: String) -> String {
        superscripts.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    /// "|EN| NEW RELEASED" -> "EN"; untagged -> nil
    static func tag(_ category: String) -> String? {
        let v = memo("tag", category) { group1(category, "^\\s*\\|\\s*([A-Z]+)\\s*\\|") ?? "" }
        return v.isEmpty ? nil : v
    }
    /// "BE| ALGEMEEN" -> "BE"
    static func country(_ category: String) -> String? {
        let v = memo("cc", category) { group1(category, "^\\s*([A-Z0-9]{2,4})\\s*\\|") ?? "" }
        return v.isEmpty ? nil : v
    }
    static func category(_ name: String) -> String {
        memo("cat", name) {
            var n = sub(name, "^\\s*\\|\\s*[A-Z]+\\s*\\|\\s*")
            n = sub(n, "^\\s*[A-Z0-9]{2,4}\\s*\\|\\s*")
            return squash(stripDecor(n))
        }
    }
    static func title(_ name: String) -> String {
        var n = sub(name, "^\\s*[A-Z0-9]{2,3}\\s*-\\s*")      // "EN - ", "4K - "
        n = sub(n, "^\\s*[A-Z]{2}\\s*\\|\\s*")                   // "BE| "
        n = stripDecor(n)
        n = sub(n, "\\s+-\\s+UNCUT\\b|\\s+4K\\b|\\s+\\([A-Z]{2}\\)$")
        return squash(n)
    }
    /// Detail and hero titles also drop the "(2025)" year suffix.
    static func display(_ name: String) -> String {
        // drop trailing "(2025)", "(MULTI SUB)", "(GB)", "(FHD HEVC)"… groups
        var n = title(name)
        while true {
            let m = sub(n, "\\s*\\([^()]*\\)\\s*$")
            if m == n || m.isEmpty { break }
            n = m
        }
        return squash(n)
    }
    static func year(_ name: String) -> String { group1(name, "\\(((19|20)\\d\\d)\\)") ?? "" }
    static let capsWords: Set<String> = ["HD", "FHD", "UHD", "VIP", "PPV", "BK", "TV", "UK", "US", "BBC", "NBA", "NFL", "NHL", "MLB",
                                         "DAZN", "ESPN", "IMDB", "4K", "RAW", "MENA", "HBO", "UFC", "WWE", "EPL", "CNN", "BEIN"]
    /// "NETFLIX KIDS" -> "Netflix Kids", keeping short codes in capitals.
    static func titleCase(_ s: String) -> String { memo("tc", s) { titleCase0(s) } }
    private static func titleCase0(_ s: String) -> String {
        s.lowercased().split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
            let word = String(w)
            if capsWords.contains(word.uppercased()) { return word.uppercased() }
            var out = "", startNext = true
            for ch in word {
                out.append(startNext ? Character(ch.uppercased()) : ch)
                startNext = "/(+-".contains(ch)
            }
            return out
        }.joined(separator: " ")
    }
    static func isSeparator(_ name: String) -> Bool {
        name.range(of: "^[#=*\\-_~|]{3,}", options: .regularExpression) != nil
    }
    static func initials(_ name: String) -> String {
        let w = name.filter { $0.isLetter || $0.isNumber || $0 == " " }.split(separator: " ")
        return String((w.first ?? "").prefix(4)).uppercased()
    }
}

// MARK: - Pictures

enum ImageSize: String { case poster = "w342", still = "w780", backdrop = "w1280" }

enum Img {
    /// TMDB pictures come as "original"; ask for the size the tile needs.
    static func url(_ s: String, _ size: ImageSize = .poster) -> URL? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let r = t.range(of: "image.tmdb.org/t/p/") {
            let rest = t[r.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            let file = rest[rest.index(after: slash)...]
            if file.isEmpty { return nil }
            return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)/\(file)")
        }
        return URL(string: t)
    }
}

func fmtTime(_ ms: Int) -> String {
    let s = max(0, ms / 1000), h = s / 3600, m = (s % 3600) / 60, x = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
}
