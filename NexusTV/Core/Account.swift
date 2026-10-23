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
struct StoredAccount: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var server: String
    var username: String
    var password: String
    var account: Account { Account(server: server, username: username, password: password) }
}

enum AccountVault {
    private static let service = "com.nexus.tv.accounts"

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
        let seed = [StoredAccount(id: "default", name: "My IPTV", server: a.server, username: a.username, password: a.password)]
        save(seed)
        return seed
    }

    @discardableResult
    static func save(_ l: [StoredAccount]) -> Bool {
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
