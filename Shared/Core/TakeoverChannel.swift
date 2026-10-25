import Foundation
import CryptoKit
import os

/// Last device wins: the account allows one stream, so the app that starts playing tells the others over ntfy.sh and they let go.
/// The topic is derived from the active source (never logged or shown); the body carries a device id, a name, a kind and a time.
protocol TakeoverTransport: Sendable {
    /// Posts the body; returns the id the SERVER gave the message (claims are ordered by it, never by device clocks).
    func publish(topic: String, body: Data) async throws -> String
    /// The raw answer of a poll: one JSON event per line.
    func poll(topic: String, since: String) async throws -> Data
}

struct NtfyTransport: TakeoverTransport {
    static let host = "https://ntfy.sh/"
    func publish(topic: String, body: Data) async throws -> String {
        guard let url = URL(string: Self.host + topic) else { throw URLError(.badURL) }
        var r = URLRequest(url: url, timeoutInterval: 8)
        r.httpMethod = "POST"; r.httpBody = body
        let d = try await URLSession.shared.data(for: r).0
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let id = o["id"] as? String, !id.isEmpty else { throw URLError(.cannotParseResponse) }
        return id
    }
    func poll(topic: String, since: String) async throws -> Data {
        guard let url = URL(string: Self.host + topic + "/json?poll=1&since=" + since) else { return Data() }
        return try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)).0
    }
}

/// The wire message: {"v":1,"dev":"<id>","name":"<name>","kind":"play","t":<ms epoch>}
struct TakeoverMessage: Codable, Equatable {
    var v = 1
    var dev: String
    var name: String
    var kind: String      // "play" = I take the stream now, "stop" = I let it go
    var t: Int
}

/// Callable from any thread (VLCController is not main-actor bound): the state sits behind a lock.
final class TakeoverChannel: @unchecked Sendable {
    static let pollSeconds: UInt64 = 3
    private static let log = Logger(subsystem: "com.nexus.tv", category: "takeover")

    /// "nxtv-" + the first 24 hex characters of SHA-256(server|username|password).
    nonisolated static func topic(server: String, username: String, password: String) -> String {
        let h = SHA256.hash(data: Data((server + "|" + username + "|" + password).utf8))
        return "nxtv-" + h.map { String(format: "%02x", $0) }.joined().prefix(24)
    }

    nonisolated static func deviceId(_ d: UserDefaults = .standard) -> String {
        if let s = d.string(forKey: "nx.dev"), !s.isEmpty { return s }
        let s = UUID().uuidString.lowercased()
        d.set(s, forKey: "nx.dev")
        return s
    }
    nonisolated static var deviceName: String {
        #if os(tvOS)
        return "Apple TV"
        #else
        return "Mac"
        #endif
    }

    let transport: TakeoverTransport
    let device: String
    let name: String
    let now: () -> Date
    private let lock = NSLock()
    private var _onLost: ((String) -> Void)?, _topic: String?, _claimT: Int?, _claimId: String?, _holding = false, _since: String?
    private var loop: Task<Void, Never>?
    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

    /// Another app took the stream; `by` is its name. Called on whatever thread polled.
    var onLost: ((String) -> Void)? { get { locked { _onLost } } set { locked { _onLost = newValue } } }
    /// Set by the player from the active source; nil = no takeover (nothing is sent or polled).
    var topic: String? { get { locked { _topic } } set { locked { _topic = newValue } } }
    /// When this app made its claim (ms epoch); nil = no claim.
    var claimT: Int? { locked { _claimT } }
    var holding: Bool { locked { _holding } }
    /// The server's id of my claim; nil until the publish answered (no id, no listening: nothing can be ordered).
    var claimId: String? { locked { _claimId } }

    init(transport: TakeoverTransport = NtfyTransport(), device: String = TakeoverChannel.deviceId(), name: String = TakeoverChannel.deviceName,
         now: @escaping () -> Date = { Date() }) {
        self.transport = transport; self.device = device; self.name = name; self.now = now
    }

    func log(_ event: String) { Self.log.info("\(event, privacy: .public)") }

    private var nowMs: Int { Int(now().timeIntervalSince1970 * 1000) }

    /// A stream is about to open (the owner caused it): publish the claim and start listening.
    func claim() {
        guard let topic else { return }
        let t = nowMs
        locked { _claimT = t; _claimId = nil; _since = nil }
        Self.log.info("takeover.claim")
        send(.init(dev: device, name: name, kind: "play", t: t), topic: topic) { [self] id in
            locked { if _claimT == t { _claimId = id; _since = id } }
        }
        hold()
    }

    /// An automatic reopen after a stall keeps the claim it already has: listening resumes, nothing is sent.
    func resumeHolding() { if claimT != nil { hold() } }


    /// The stream is closed (stopped, released, backgrounded): no polling.
    func pause() { locked { _holding = false; loop?.cancel(); loop = nil } }

    /// The player leaves for good: tell the others, forget the claim.
    func leave() {
        let had = claimT != nil
        pause(); locked { _claimT = nil; _claimId = nil }
        if had, let topic { send(.init(dev: device, name: name, kind: "stop", t: nowMs), topic: topic) }
    }

    private func hold() {
        lock.lock(); defer { lock.unlock() }
        _holding = true
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.pollOnce()
            }
        }
    }

    private func send(_ m: TakeoverMessage, topic: String, done: (@Sendable (String) -> Void)? = nil) {
        guard let body = try? JSONEncoder().encode(m) else { return }
        let tr = transport
        Task {
            for attempt in 0..<2 {
                do { let id = try await tr.publish(topic: topic, body: body); done?(id); return }
                catch { Self.log.error("takeover.err publish"); if attempt == 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) } }
            }
        }
    }

    /// One poll. Does nothing unless this app holds a stream with a claim the server has numbered. The poll asks for what came
    /// after my claim, so a "play" from another device in the answer is newer than mine by the server's order: lost.
    func pollOnce() async {
        guard holding, let topic, let mine = claimT, let since = locked({ _since }) else { return }
        let data: Data
        do { data = try await transport.poll(topic: topic, since: since) } catch { Self.log.error("takeover.err poll"); return }
        guard holding, claimT == mine else { return }
        for ev in Self.events(data) {
            locked { if _claimT == mine { _since = ev.id } }
            guard let m = ev.message, m.v == 1, m.dev != device, m.kind == "play" else { continue }
            Self.log.info("takeover.lost")
            pause(); locked { _claimT = nil; _claimId = nil }
            onLost?(m.name)
            return
        }
    }

    /// The events of a poll answer, in order: (ntfy id, the message inside when it is ours to read).
    nonisolated static func events(_ data: Data) -> [(id: String, message: TakeoverMessage?)] {
        var out: [(String, TakeoverMessage?)] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], (o["event"] as? String) == "message",
                  let id = o["id"] as? String else { continue }
            let body = (o["message"] as? String).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(TakeoverMessage.self, from: $0) }
            out.append((id, body))
        }
        return out
    }
}
