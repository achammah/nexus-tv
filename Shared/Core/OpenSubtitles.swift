import Foundation
import Security

/// Online subtitles from OpenSubtitles (api.opensubtitles.com/api/v1). The owner's own account (API key, username,
/// password) is kept in the Keychain; nothing is built into the app. Searching is free; each download counts toward
/// the account's daily quota, so a download happens only on a pick, or for the next episode once the owner chose
/// online subtitles for that series.
struct OSAccount: Codable, Equatable { var key: String, user: String, pass: String }

struct OSResult: Identifiable, Hashable, Sendable {
    let fileId: Int, lang: String, release: String, downloads: Int, hearingImpaired: Bool, trusted: Bool
    var fps: Double = 0
    var exact = false          // OpenSubtitles says it was made for this very file (moviehash match)
    /// Quality points: a frame rate given (+1), a named release (web, blu-ray, hdtv, a streaming service: +2), a trusted uploader (+1).
    var quality: Int {
        let named = release.range(of: "web|blu-?ray|bdrip|brrip|hdtv|amzn|\\bnf\\b|dsnp|hmax|atvp", options: [.regularExpression, .caseInsensitive]) != nil
        return (fps > 0 ? 1 : 0) + (named ? 2 : 0) + (trusted ? 1 : 0)
    }
    var id: Int { fileId }
}

/// What to search for: a film by its TMDb id, or an episode by the series' TMDb id, season and episode.
enum OSQuery: Equatable { case film(tmdb: String), episode(seriesTmdb: String, season: Int, episode: Int) }

@MainActor
final class OpenSubtitles: ObservableObject {
    static let shared = OpenSubtitles()
    private static let service = "com.nexus.tv.opensubtitles"
    private static let ua = "NexusTV v1.0"

    @Published private(set) var account: OSAccount? = OpenSubtitles.loadAccount()
    @Published private(set) var left: Int? = nil
    private var token: (value: String, base: String, at: Date)? = nil
    var ready: Bool { account?.key.isEmpty == false }

    enum Failure: LocalizedError {
        case http(Int, String), noAccount, noLink
        var errorDescription: String? {
            switch self {
            case .http(let c, let m): return m.isEmpty ? "HTTP \(c)" : m
            case .noAccount: return "No OpenSubtitles account. Add one in Settings › Subtitles."
            case .noLink: return "OpenSubtitles gave no download link."
            }
        }
    }

    // MARK: account

    /// Checks the login with /login, then keeps the account. A wrong login keeps the previous one.
    func signIn(_ a: OSAccount) async throws {
        let (t, l) = try await Self.login(a)
        token = t; left = l
        account = a
        Self.saveAccount(a)
    }
    func signOut() { account = nil; token = nil; left = nil; Self.saveAccount(nil) }

    private static func login(_ a: OSAccount) async throws -> ((value: String, base: String, at: Date), Int?) {
        let d = try await request(a.key, "POST", "https://api.opensubtitles.com/api/v1/login", body: ["username": a.user, "password": a.pass], bearer: nil)
        guard let tok = d["token"] as? String else { throw Failure.http(401, "Login refused") }
        let base = (d["base_url"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "api.opensubtitles.com"
        let user = d["user"] as? [String: Any]
        let left = (user?["remaining_downloads"] as? Int) ?? (user?["allowed_downloads"] as? Int)
        return ((tok, base, Date()), left)
    }
    private func validToken() async throws -> (value: String, base: String, at: Date) {
        guard let a = account else { throw Failure.noAccount }
        if let t = token, Date().timeIntervalSince(t.at) < 20 * 3600 { return t }
        let (t, l) = try await Self.login(a)
        token = t; if let l { left = l }
        return t
    }

    // MARK: search and download

    /// The best subtitle per language, languages in the owner's order: same language first, then not for the
    /// hearing impaired, trusted uploaders, most downloaded. Machine or AI translations and multi-part files are left out.
    /// Ranked: language (owner's order), exact-file match, same frame rate as the file, quality points, not for the
    /// hearing impaired, most downloaded. One per language, the best one.
    func search(_ q: OSQuery, languages: [String], hash: String? = nil, fps: Double = 0) async throws -> [OSResult] {
        guard let a = account else { throw Failure.noAccount }
        var p: [String]
        switch q {
        case .film(let t): p = ["tmdb_id=\(t)"]
        case .episode(let t, let s, let e): p = ["parent_tmdb_id=\(t)", "season_number=\(s)", "episode_number=\(e)"]
        }
        if let hash, !hash.isEmpty { p.append("moviehash=" + hash) }
        p.append("languages=" + languages.sorted().joined(separator: ","))
        p.append("order_by=download_count")
        let d = try await Self.request(a.key, "GET", "https://api.opensubtitles.com/api/v1/subtitles?" + p.joined(separator: "&"), body: nil, bearer: nil)
        var out: [OSResult] = []
        for r in d["data"] as? [[String: Any]] ?? [] {
            let at = r["attributes"] as? [String: Any] ?? [:]
            guard let f = (at["files"] as? [[String: Any]])?.first, let id = f["file_id"] as? Int,
                  (at["machine_translated"] as? Bool) != true, (at["ai_translated"] as? Bool) != true, ((at["nb_cd"] as? Int) ?? 1) <= 1 else { continue }
            var r = OSResult(fileId: id, lang: (at["language"] as? String) ?? "", release: (at["release"] as? String) ?? (f["file_name"] as? String) ?? "",
                             downloads: (at["download_count"] as? Int) ?? 0, hearingImpaired: (at["hearing_impaired"] as? Bool) ?? false,
                             trusted: (at["from_trusted"] as? Bool) ?? false)
            r.fps = (at["fps"] as? Double) ?? Double((at["fps"] as? String) ?? "") ?? 0
            r.exact = (at["moviehash_match"] as? Bool) ?? false
            out.append(r)
        }
        func sameFps(_ r: OSResult) -> Bool { fps > 0 && r.fps > 0 && abs(r.fps - fps) < 0.05 }
        out.sort { x, y in
            let lx = languages.firstIndex(of: x.lang) ?? 99, ly = languages.firstIndex(of: y.lang) ?? 99
            if lx != ly { return lx < ly }
            if x.exact != y.exact { return x.exact }
            if sameFps(x) != sameFps(y) { return sameFps(x) }
            if x.quality != y.quality { return x.quality > y.quality }
            if x.hearingImpaired != y.hearingImpaired { return !x.hearingImpaired }
            return x.downloads > y.downloads
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.lang).inserted }
    }

    /// One download (counts toward the daily quota): the SRT is saved to a temporary file for the player.
    func download(_ r: OSResult) async throws -> URL {
        guard let a = account else { throw Failure.noAccount }
        let t = try await validToken()
        let d = try await Self.request(a.key, "POST", "https://\(t.base)/api/v1/download", body: ["file_id": r.fileId, "sub_format": "srt"], bearer: t.value)
        guard let link = (d["link"] as? String).flatMap(URL.init(string:)) else { throw Failure.noLink }
        if let rem = d["remaining"] as? Int { left = rem }
        let (data, resp) = try await URLSession.shared.data(from: link)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw Failure.http(h.statusCode, "") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("osub-\(r.fileId).srt")
        try data.write(to: file)
        return file
    }

    private static func request(_ key: String, _ method: String, _ url: String, body: [String: Any]?, bearer: String?) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw Failure.http(0, "Bad address") }
        var r = URLRequest(url: u, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "Api-Key")
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { r.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (d, resp) = try await URLSession.shared.data(for: r)
        let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            let msg = (j["message"] as? String) ?? ((j["errors"] as? [String])?.first) ?? ""
            throw Failure.http(h.statusCode, msg)
        }
        return j
    }

    // MARK: file hash

    private var hashes: [URL: String] = [:]
    /// OpenSubtitles file hash: the size plus the 64-bit sum (little-endian words) of the first and last 64 KB,
    /// read with two Range requests. "" when the server does not allow ranges.
    func fileHash(_ url: URL) async -> String {
        if let h = hashes[url] { return h }
        let c = 65_536
        func chunk(_ range: String) async -> (Data, String?)? {
            var r = URLRequest(url: url, timeoutInterval: 15)
            r.setValue("bytes=" + range, forHTTPHeaderField: "Range")
            r.setValue("Mozilla/5.0 (AppleTV) NexusTV/1.0", forHTTPHeaderField: "User-Agent")
            guard let (d, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse, h.statusCode == 206 else { return nil }
            return (d, h.value(forHTTPHeaderField: "Content-Range"))
        }
        guard let (head, cr) = await chunk("0-\(c - 1)"), let size = cr.flatMap({ UInt64($0.split(separator: "/").last ?? "") }), size > UInt64(c * 2),
              let (tail, _) = await chunk("\(size - UInt64(c))-\(size - 1)") else { hashes[url] = ""; return "" }
        var h = size
        for d in [head, tail] {
            d.withUnsafeBytes { raw in
                var i = 0
                while i + 8 <= raw.count { h = h &+ UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: UInt64.self)); i += 8 }
            }
        }
        let out = String(format: "%016llx", h)
        hashes[url] = out
        return out
    }

    // MARK: Keychain

    private static func loadAccount() -> OSAccount? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(OSAccount.self, from: d)
    }
    private static func saveAccount(_ a: OSAccount?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard let a, let d = try? JSONEncoder().encode(a) else { return }
        var add = q
        add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    /// Test hook (debug builds): -NXResetOSub YES forgets the account.
    static func resetForTests() { saveAccount(nil) }

    /// Settings languages (catalogue tags) as OpenSubtitles language codes; English and French when none map.
    static func languages(_ tags: [String]) -> [String] {
        let map = ["EN": "en", "FR": "fr", "QC": "fr", "NL": "nl", "DE": "de", "ES": "es", "IT": "it", "AR": "ar", "PL": "pl", "TR": "tr", "PT": "pt-PT"]
        var out: [String] = []
        for t in tags { if let l = map[t], !out.contains(l) { out.append(l) } }
        return out.isEmpty ? ["en", "fr"] : out
    }
    static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}
