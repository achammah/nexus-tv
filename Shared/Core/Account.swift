import Foundation
import Security

struct Account: Codable, Equatable {
    var server: String
    var username: String
    var password: String

    var base: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.isEmpty && !s.contains("://") { s = "http://" + s }
        return s
    }
    var isComplete: Bool { !base.isEmpty && !username.isEmpty && !password.isEmpty }
}

/// The single login of the first builds, kept in the Keychain; read once to seed the account list, never written now.
/// The app ships with no account: the owner adds one on first launch.
enum Keychain {
    private static let service = "com.nexus.tv.account"

    static func load() -> Account? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: d)
    }

    @discardableResult
    static func save(_ a: Account) -> Bool {
        guard let d = try? JSONEncoder().encode(a) else { return false }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func current() -> Account? { load() }

    static func remove() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// Every IPTV login the owner added. Kept in the Keychain as one item; the active id in UserDefaults.
struct StoredAccount: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Xtream: the server · M3U: the playlist link · Portal: the portal link.
    var server: String
    var username: String
    var password: String
    var type: SourceType = .xtream
    /// M3U: the TV guide link (XMLTV), the one typed or the one the playlist header names.
    var epg: String = ""
    /// Portal: the MAC address.
    var mac: String = ""
    /// M3U over the keep limit: the groups the owner kept (nil = everything).
    var groups: [String]? = nil
    /// A line shown under the name in Sources ("Recognised as an Xtream link: full library").
    var note: String = ""
    var account: Account { Account(server: server, username: username, password: password) }

    init(id: String, name: String, server: String, username: String, password: String, type: SourceType = .xtream,
         epg: String = "", mac: String = "", groups: [String]? = nil, note: String = "") {
        self.id = id; self.name = name; self.server = server; self.username = username; self.password = password
        self.type = type; self.epg = epg; self.mac = mac; self.groups = groups; self.note = note
    }
    // accounts saved by earlier builds have no type: they are Xtream logins
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        server = try c.decode(String.self, forKey: .server)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        type = try c.decodeIfPresent(SourceType.self, forKey: .type) ?? .xtream
        epg = try c.decodeIfPresent(String.self, forKey: .epg) ?? ""
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        groups = try c.decodeIfPresent([String].self, forKey: .groups)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
    enum K: String, CodingKey { case id, name, server, username, password, type, epg, mac, groups, note }

    /// The adapter that reads this source.
    func makeSource() -> LibrarySource? {
        switch type {
        case .xtream: return XtreamSource(account: account)
        case .m3u:
            guard let u = URL(string: Account(server: server, username: "x", password: "x").base) else { return nil }
            return M3USource(url: u, epg: epg, keptGroups: groups)
        case .portal: return PortalSource(base: server, mac: mac)
        }
    }
}

enum AccountVault {
    private static let service = "com.nexus.tv.accounts"
    /// Debug captures: a window that shows sample sources must never write the shared Keychain.
    static var readOnly = false

    static var activeId: String {
        get { UserDefaults.standard.string(forKey: "nx.activeAccount") ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "nx.activeAccount") }
    }

    /// The list; on first use it is seeded with the single account the first builds kept (none on a new install).
    static func list() -> [StoredAccount] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
           let l = try? JSONDecoder().decode([StoredAccount].self, from: d), !l.isEmpty { return l }
        guard let a = Keychain.current() else { return [] }
        let seed = [StoredAccount(id: "default", name: "My library", server: a.server, username: a.username, password: a.password)]
        save(seed)
        return seed
    }

    @discardableResult
    static func save(_ l: [StoredAccount]) -> Bool {
        if readOnly { return true }
        guard let d = try? JSONEncoder().encode(l) else { return false }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Forgets every account (test hook -NXResetAccounts YES, debug builds only).
    static func removeAll() {
        if readOnly { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        Keychain.remove()
        UserDefaults.standard.removeObject(forKey: "nx.activeAccount")
    }

    static func active() -> StoredAccount? {
        let l = list()
        return l.first { $0.id == activeId } ?? l.first
    }

    /// Checks a login with player_api.php (user_info.auth == 1) before it is saved.
    static func check(_ a: Account) async -> String? {
        do {
            let d = try await Xtream(account: a).data(nil)
            let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let ui = j?["user_info"] as? [String: Any]
            let auth = (ui?["auth"] as? NSNumber)?.intValue ?? Int((ui?["auth"] as? String) ?? "") ?? 0
            guard auth == 1 else { return "The provider refused this login." }
            // a login can still pass once the subscription has ended; the lists are then refused
            let status = (ui?["status"] as? String) ?? "Active"
            return status.caseInsensitiveCompare("Active") == .orderedSame ? nil : "The provider says this subscription is \(status.lowercased())."
        } catch Xtream.Failure.http {
            return "The provider refused this login."   // this provider answers a wrong login with an HTTP error (513)
        } catch {
            return "Could not reach the server (\(error.localizedDescription))."
        }
    }
}

/// Xtream Codes API: player_api.php actions + stream URLs.
struct Xtream {
    let account: Account

    enum Failure: Error { case badURL, http(Int) }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 600
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (AppleTV) NexusTV/1.0"]
        return URLSession(configuration: c)
    }()

    func apiURL(_ action: String?, _ params: [String: String] = [:]) -> URL? {
        var comps = URLComponents(string: account.base + "/player_api.php")
        var items = [URLQueryItem(name: "username", value: account.username), URLQueryItem(name: "password", value: account.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in params.sorted(by: { $0.key < $1.key }) { items.append(URLQueryItem(name: k, value: v)) }
        comps?.queryItems = items
        return comps?.url
    }

    func data(_ action: String?, _ params: [String: String] = [:]) async throws -> Data {
        guard let url = apiURL(action, params) else { throw Failure.badURL }
        let (d, r) = try await Self.session.data(from: url)
        if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw Failure.http(h.statusCode) }
        return d
    }

    /// Large lists go to a file first, so the app never holds two copies in memory.
    func download(_ action: String, to file: URL) async throws {
        guard let url = apiURL(action) else { throw Failure.badURL }
        let (tmp, r) = try await Self.session.download(from: url)
        if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw Failure.http(h.statusCode) }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
    }

    func list<T: Decodable>(_ type: T.Type, _ action: String, _ params: [String: String] = [:]) async throws -> [T] {
        let d = try await data(action, params)
        return (try? JSONDecoder().decode([T].self, from: d)) ?? []
    }

    func json(_ action: String, _ params: [String: String]) async throws -> [String: Any] {
        let d = try await data(action, params)
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    private func path(_ kind: String, _ id: String, _ ext: String) -> URL? {
        let u = account.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.username
        let p = account.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.password
        return URL(string: "\(account.base)/\(kind)/\(u)/\(p)/\(id).\(ext)")
    }
    func liveURL(_ id: String) -> URL? { path("live", id, "m3u8") }
    func filmURL(_ id: String, _ ext: String) -> URL? { path("movie", id, ext.isEmpty ? "mp4" : ext) }
    func episodeURL(_ id: String, _ ext: String) -> URL? { path("series", id, ext.isEmpty ? "mkv" : ext) }
}
