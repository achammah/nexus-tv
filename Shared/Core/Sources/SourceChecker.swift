import Foundation

/// Checks a source before it is saved, and builds the saved record.
enum SourceChecker {
    struct Outcome: Equatable, Sendable {
        var stage: CheckStage
        var account: StoredAccount?
        var note: String = ""
    }

    /// Values: the three form rows as typed (Xtream: server, username, password · M3U: link, guide, name · Portal: link, MAC, name).
    static func check(_ type: SourceType, _ v: [String]) async -> Outcome {
        let v = (v + ["", "", ""]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let id = "a\(Int(Date().timeIntervalSince1970))"
        switch type {
        case .xtream:
            let a = Account(server: v[0], username: v[1], password: v[2])
            let st = await xtream(a)
            return Outcome(stage: st, account: st == .ok ? StoredAccount(id: id, name: v[1], server: a.base, username: v[1], password: v[2]) : nil)
        case .m3u:
            if let link = XtreamLink.parse(v[0]) {
                // an export link signs in through the Xtream adapter: full library, not a download
                let a = Account(server: link.base, username: link.user, password: link.pass)
                let st = await xtream(a)
                let name = v[2].isEmpty ? link.user : v[2]
                return Outcome(stage: st, account: st == .ok ? StoredAccount(id: id, name: name, server: a.base, username: link.user, password: link.pass, note: "Recognised as an Xtream link: full library") : nil,
                               note: "Recognised as an Xtream link: full library")
            }
            let base = Account(server: v[0], username: "x", password: "x").base
            guard let url = URL(string: base) else { return Outcome(stage: .server) }
            let src = M3USource(url: url, epg: v[1])
            src.start()
            defer { src.cancel() }
            do { try await src.waitForFirst() }
            catch let e as SourceError {
                switch e { case .refused: return Outcome(stage: .auth); case .notAPlaylist: return Outcome(stage: .invalid); case .cancelled: return Outcome(stage: .cancel); case .unreachable: return Outcome(stage: .server) }
            } catch { return Outcome(stage: .server) }
            let guide = v[1].isEmpty ? src.store.guide : v[1]
            return Outcome(stage: .ok, account: StoredAccount(id: id, name: v[2].isEmpty ? "My playlist" : v[2], server: base, username: "", password: "", type: .m3u, epg: guide))
        case .portal:
            let mac = v[1].uppercased()
            guard PortalSource.validMAC(mac) else { return Outcome(stage: .auth) }
            let p = PortalSource(base: v[0], mac: mac)
            do { try await p.ensure() }
            catch let e as SourceError { return Outcome(stage: e == .refused ? .auth : .server) }
            catch { return Outcome(stage: .server) }
            return Outcome(stage: .ok, account: StoredAccount(id: id, name: v[2].isEmpty ? "My portal" : v[2], server: p.base, username: "", password: "", type: .portal, mac: mac))
        }
    }

    /// player_api.php answers user_info.auth == 1 for a good login. server = no answer, auth = refused or ended.
    static func xtream(_ a: Account) async -> CheckStage {
        guard a.isComplete else { return .auth }
        do {
            let d = try await Xtream(account: a).data(nil)
            let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let ui = j?["user_info"] as? [String: Any]
            let auth = (ui?["auth"] as? NSNumber)?.intValue ?? Int((ui?["auth"] as? String) ?? "") ?? 0
            guard auth == 1 else { return .auth }
            let status = (ui?["status"] as? String) ?? "Active"
            return status.caseInsensitiveCompare("Active") == .orderedSame ? .ok : .auth
        } catch Xtream.Failure.http { return .auth }
        catch { return .server }
    }

    /// Per type and stage: the message and which of the three rows turn red (a green mark for a row that passed).
    static func failure(_ type: SourceType, _ stage: CheckStage, xtreamLink: Bool = false) -> (message: String, marks: [RowMark]) {
        if xtreamLink {
            return stage == .auth ? ("Server reached, but it refused the login in this link.", [.bad, .none, .none])
                                  : ("Could not reach this server. Check the link and the network.", [.bad, .none, .none])
        }
        switch (type, stage) {
        case (.xtream, .auth): return ("Server reached, but it refused this username and password.", [.ok, .bad, .bad])
        case (.xtream, _): return ("Could not reach this server. Check the address and the network.", [.bad, .none, .none])
        case (.m3u, .auth): return ("That server refused the link.", [.bad, .none, .none])
        case (.m3u, .invalid): return ("This link is not a playlist.", [.bad, .none, .none])
        case (.m3u, .cancel): return ("Playlist not loaded. Press Sign in to try again.", [.none, .none, .none])
        case (.m3u, _): return ("Could not reach this link. Check the address and the network.", [.bad, .none, .none])
        case (.portal, .auth): return ("Portal reached, but it refused this MAC address.", [.ok, .bad, .none])
        case (.portal, _): return ("Could not reach this portal. Check the address and the network.", [.bad, .none, .none])
        }
    }
}
