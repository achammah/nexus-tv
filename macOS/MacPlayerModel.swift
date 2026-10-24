import SwiftUI
import Combine

/// Everything the Mac player does around VLC: start and resume, reconnect after a drop (1, 2, 4, 8, 16 s),
/// remembered audio and subtitles per film / series, online subtitles (OpenSubtitles) with Earlier / Later,
/// the next episode (found from the series when it was not given) and the next-episode card near the end.
/// The same rules as the Apple TV player.
@MainActor
final class MacPlayerModel: ObservableObject {
    let vlc = VLCController()
    @Published var item: MediaItem
    @Published var startMs: Int
    @Published var list: [MediaItem]
    @Published var index: Int
    @Published var next: [MediaItem]
    @Published var picture: String
    @Published var reconnecting = false
    @Published var attempts = 0
    @Published var upLeft = 0
    @Published var online: [OSResult] = []
    @Published var onlineState = ""
    @Published var onlineActive: Int? = nil
    @Published var onlineTrack: Int? = nil
    @Published var message: String? = nil
    private var onlineFor = ""
    private var onlineFiles: [Int: URL] = [:]
    private var upDone = false
    private var upTask: Task<Void, Never>?
    private var retryPending = false
    private var lastSave = Date.distantPast
    private var catalog: Catalog!
    private var user: UserStore!
    private var languages: [String] = []
    private var subs: Set<AnyCancellable> = []
    /// Called when the window should close (the end of the last episode or a film).
    var onEnd: (() -> Void)?
    static let upAtMs = 40_000, upCount = 10

    var isLive: Bool { item.kind == .live }
    var title: String { item.kind == .episode ? item.name.replacingOccurrences(of: " · S", with: " — Season ").replacingOccurrences(of: " E", with: " · Episode ") : item.name }

    init(_ p: MacPlay) {
        item = p.item; startMs = p.startMs; list = p.list; index = p.index; next = p.next; picture = p.picture
    }

    func attach(catalog: Catalog, user: UserStore, languages: [String]) {
        self.catalog = catalog; self.user = user; self.languages = languages
        guard subs.isEmpty else { return }
        // VLC's state drives the session (the window only draws it)
        vlc.$started.removeDuplicates().filter { $0 }.sink { [weak self] _ in self?.started(); self?.loadOnlineIfNeeded() }.store(in: &subs)
        vlc.$trouble.dropFirst().sink { [weak self] _ in self?.troubled() }.store(in: &subs)
        vlc.$ended.removeDuplicates().filter { $0 }.sink { [weak self] _ in if self?.finished() == false { self?.onEnd?() } }.store(in: &subs)
        vlc.$timeMs.sink { [weak self] _ in self?.tick() }.store(in: &subs)
    }

    // MARK: playback

    func start(again: Bool = false) {
        guard let url = catalog.url(item) else { vlc.failed = true; return }
        if !again { attempts = 0; reconnecting = false; upDone = false }
        autoSync.stop()      // a new stream: its own reference
        if onlineFor != item.key { online = []; onlineState = ""; onlineActive = nil; onlineTrack = nil; onlineFiles = [:] } else { onlineTrack = nil }
        vlc.play(url, startMs: startMs, live: isLive)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "NXMute") { vlc.player.audio?.isMuted = true }     // checks that run while the owner works
        #endif
        if !isLive { user.setResume(item, posMs: startMs, durMs: 0) }
        lastSave = Date()
        if item.kind == .episode && next.isEmpty { Task { await loadNextEpisodes() } }
    }

    func started() {
        reconnecting = false
        let a = attempts
        Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if vlc.started && attempts == a { attempts = 0 } }
        guard !isLive else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)     // tracks are known and the player accepts changes
            user.learnSubs(item, vlc.subtitleTracks.contains { $0.0 >= 0 })
            applyTrackPrefs()
        }
    }

    func stop() { saveResume(); upHide(); vlc.stop() }

    /// The stream stopped: reopen it (live: the live edge; films: the last position), 1, 2, 4, 8, 16 s apart.
    func troubled() {
        guard !retryPending else { return }
        attempts += 1
        if attempts > 5 { vlc.stop(); vlc.failed = true; reconnecting = false; return }
        reconnecting = true; retryPending = true
        let at = isLive ? 0 : max(vlc.timeMs, startMs)
        saveResume()
        vlc.stop()
        let delay = UInt64(1 << (attempts - 1))
        Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            retryPending = false
            guard reconnecting else { return }
            startMs = at
            start(again: true)
        }
    }

    func seek(by ms: Int) { vlc.seek(toMs: vlc.timeMs + ms) }

    func zap(_ d: Int) {
        guard isLive, !list.isEmpty else { return }
        index = (index + d + list.count) % list.count
        item = list[index]
        start()
    }

    func tick() {
        guard !isLive, vlc.timeMs > 0 else { return }
        if Date().timeIntervalSince(lastSave) >= 15 { lastSave = Date(); user.setResume(item, posMs: vlc.timeMs, durMs: vlc.lengthMs) }
        upCheck()
    }

    func saveResume() {
        guard !isLive, !vlc.ended, vlc.started else { return }
        user.setResume(item, posMs: vlc.timeMs, durMs: vlc.lengthMs)
    }

    /// The end of a film or episode: the next episode plays, or the window closes.
    func finished() -> Bool {
        if !isLive { user.finished(item) }
        if !next.isEmpty { playNext(); return true }
        return false
    }

    func playNext() {
        upHide()
        guard let n = next.first else { return }
        saveResume()
        item = n
        startMs = user.resumePoint(n)?.posMs ?? 0
        next = Array(next.dropFirst())
        start()
    }

    /// Started from Continue watching or a search: the episodes that follow come from the series.
    private func loadNextEpisodes() async {
        guard let sid = item.seriesId, let d = await catalog.details(MediaItem(kind: .series, id: sid, name: item.seriesName ?? "")) else { return }
        let all = d.seasons.flatMap { s in (d.episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == item.id }) else { return }
        let title = item.seriesName ?? d.name
        next = all.dropFirst(i + 1).map { s, e in
            MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s) E\(e.num)", img: e.still.isEmpty ? d.poster : e.still, ext: e.ext, sub: e.title,
                      seriesId: sid, seriesName: title)
        }
    }

    // MARK: next-episode card (40 s before the end of an episode longer than 80 s, 10 s countdown, once)

    private func upCheck() {
        // only while this item plays: right after a switch the clock still shows the previous episode's end
        guard vlc.started, upLeft == 0, !upDone, !next.isEmpty, vlc.lengthMs > Self.upAtMs * 2, vlc.lengthMs - vlc.timeMs <= Self.upAtMs else { return }
        upDone = true
        upLeft = Self.upCount
        upTask?.cancel()
        upTask = Task {
            while !Task.isCancelled && upLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                upLeft -= 1
            }
            if !Task.isCancelled { playNext() }
        }
    }
    func upHide() { upTask?.cancel(); upTask = nil; upLeft = 0 }

    // MARK: tracks

    /// The owner's choice for this film / series: language first, position as fallback; subtitles off by default.
    func choose(audio t: (Int, String)) {
        let list = vlc.audioTracks
        let pos = list.firstIndex { $0.0 == t.0 }
        vlc.setAudio(t.0)
        user.setTrackPref(item) { $0.audioLang = VLCController.trackName(t.1); $0.audioPos = pos }
        let want = t.0, name = vlc.audioLabel(t, in: list)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if vlc.audioIndex != want { vlc.setAudio(want); try? await Task.sleep(nanoseconds: 1_500_000_000) }
            if vlc.audioIndex != want {
                let kept = vlc.audioTracks.first { $0.0 == vlc.audioIndex }.map { vlc.audioLabel($0, in: list) } ?? "no track"
                show("Could not switch to \(name): the player stayed on \(kept)")
            }
        }
    }
    func choose(subtitle t: (Int, String)) {
        let real = vlc.subtitleTracks.filter { $0.0 >= 0 && $0.0 != onlineTrack }
        vlc.setSubtitle(t.0)
        onlineActive = nil; autoSync.stop()
        user.setTrackPref(item) {
            $0.subOff = t.0 < 0; $0.subLang = t.0 >= 0 ? VLCController.trackName(t.1) : nil
            $0.subPos = real.firstIndex { $0.0 == t.0 }; $0.subOnline = nil
        }
    }

    private func applyTrackPrefs() {
        let p = user.trackPref(item)
        func pick(_ list: [(Int, String)], lang: String?, pos: Int?) -> Int? {
            let real = list.filter { $0.0 >= 0 }
            if let lang, let m = real.first(where: { VLCController.trackName($0.1).caseInsensitiveCompare(lang) == .orderedSame }) { return m.0 }
            if let pos, real.indices.contains(pos) { return real[pos].0 }
            return nil
        }
        if let a = pick(vlc.audioTracks, lang: p?.audioLang, pos: p?.audioPos), a != vlc.audioIndex {
            vlc.setAudio(a)
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); if vlc.audioIndex != a { vlc.setAudio(a) } }
        }
        if let lang = p?.subOnline, OpenSubtitles.shared.ready {
            Task {
                if onlineFor != item.key || online.isEmpty { await loadOnline() }
                if let r = online.first(where: { $0.lang == lang }) { await pickOnline(r, remember: false) }
            }
        } else if p?.subOff ?? true { vlc.setSubtitle(-1) }
        else if let s = pick(vlc.subtitleTracks, lang: p?.subLang, pos: p?.subPos) { vlc.setSubtitle(s) }
    }

    // MARK: online subtitles

    private func onlineQuery() async -> OSQuery? {
        if item.kind == .film {
            guard let d = await catalog.details(item), !d.tmdb.isEmpty else { return nil }
            return .film(tmdb: d.tmdb)
        }
        guard item.kind == .episode, let sid = item.seriesId,
              let m = item.name.range(of: "S(\\d+) E(\\d+)$", options: .regularExpression) else { return nil }
        let nums = item.name[m].split(separator: " ").map { Int($0.filter(\.isNumber)) ?? 0 }
        guard nums.count == 2, let d = await catalog.details(MediaItem(kind: .series, id: sid, name: item.seriesName ?? "")), !d.tmdb.isEmpty else { return nil }
        return .episode(seriesTmdb: d.tmdb, season: nums[0], episode: nums[1])
    }

    func loadOnline() async {
        let key = item.key
        onlineFor = key; onlineState = "loading"; online = []
        guard let q = await onlineQuery() else { onlineState = "This title has no TMDb id: no online search."; return }
        do {
            var hash = ""
            if let u = catalog.url(item) { hash = await OpenSubtitles.shared.fileHash(u) }
            let r = try await OpenSubtitles.shared.search(q, languages: OpenSubtitles.languages(languages), hash: hash, fps: vlc.fps)
            guard onlineFor == key else { return }
            online = r; onlineState = r.isEmpty ? "No online subtitles in your languages." : "done"
            Metrics.shared.mark("player.osub hash=\(hash.isEmpty ? "none" : "ok") fps=\(String(format: "%.3f", vlc.fps)) exact=\(r.filter(\.exact).count) results=\(r.count)")
            #if DEBUG
            // test hook: -NXPickOnline fr picks the first online subtitle in that language (a check with no mouse)
            if let l = UserDefaults.standard.string(forKey: "NXPickOnline"), onlineActive == nil, let p = r.first(where: { $0.lang == l }) {
                await pickOnline(p, remember: false)
            }
            #endif
        } catch {
            if onlineFor == key { onlineState = "Online search failed (\(error.localizedDescription))." }
        }
    }
    func loadOnlineIfNeeded() { if OpenSubtitles.shared.ready && onlineFor != item.key { Task { await loadOnline() } } }

    func pickOnline(_ r: OSResult, remember: Bool) async {
        do {
            let url: URL
            if let f = onlineFiles[r.fileId] { url = f } else { url = try await OpenSubtitles.shared.download(r); onlineFiles[r.fileId] = url }
            guard let n = await vlc.addSubtitleFile(url) else { show("Online subtitles could not be shown"); return }
            onlineActive = r.fileId; onlineTrack = n
            vlc.subtitleDelayMs = Self.savedDelay(r.fileId)
            Metrics.shared.mark("player.osub added lang=\(r.lang) track=\(n) exact=\(r.exact) delay=\(vlc.subtitleDelayMs)")
            if remember { user.setTrackPref(item) { $0.subOff = false; $0.subOnline = r.lang; $0.subLang = nil; $0.subPos = nil } }
            await startAutoSync(r, file: url)
        } catch { show("Online subtitles failed (\(error.localizedDescription))") }
    }

    /// Live realignment of an online subtitle not made for this exact file (Shared/Core/SubAutoSync.swift); the next
    /// candidates of the same language are tried when this one was timed for another cut.
    private lazy var autoSync = SubAutoSync(vlc: vlc)
    private func startAutoSync(_ r: OSResult, file: URL) async {
        guard let stream = catalog.url(item) else { return }
        let rest = Array(online.filter { $0.lang == r.lang }.drop { $0.fileId != r.fileId }.dropFirst())
        await autoSync.start(stream: stream, pick: r, file: file, candidates: rest, switchTo: { [weak self] next in
            guard let self else { return nil }
            do {
                let url: URL
                if let f = self.onlineFiles[next.fileId] { url = f } else { url = try await OpenSubtitles.shared.download(next); self.onlineFiles[next.fileId] = url }
                guard let n = await self.vlc.addSubtitleFile(url) else { return nil }
                self.onlineActive = next.fileId; self.onlineTrack = n
                return url
            } catch { return nil }
        }, log: { Metrics.shared.mark($0) })
    }

    func shiftDelay(_ ms: Int) {
        guard let fid = onlineActive else { return }
        if autoSync.fileId == fid { _ = autoSync.shift(ms) } else {    // on top of the found offset
            vlc.subtitleDelayMs += ms
            var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
            all[String(fid)] = vlc.subtitleDelayMs
            UserDefaults.standard.set(all, forKey: "nx.subDelay")
        }
        objectWillChange.send()
    }
    static func savedDelay(_ fid: Int) -> Int { SubAutoSync.savedDelay(fid) }

    static func releaseHint(_ release: String) -> String {
        let r = release.replacingOccurrences(of: ".", with: " ")
        guard let m = r.range(of: "\\b((2160p|1080p|720p|480p)\\s+)?(WEB-?DL|WEBRip|WEB|Blu-?Ray|BDRip|BRRip|HDTV|AMZN|NF|DSNP|HMAX|ATVP)\\b", options: [.regularExpression, .caseInsensitive]) else { return "" }
        return " · " + r[m].trimmingCharacters(in: .whitespaces)
    }

    func show(_ s: String) {
        message = s
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if message == s { message = nil } }
    }
}
