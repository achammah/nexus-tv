import SwiftUI
import AppKit
import Combine
import VLCKit

/// Everything the Mac player does around VLC: start and resume, reconnect after a drop (1, 2, 4, 8, 16 s),
/// remembered audio and subtitles per film / series, online subtitles (OpenSubtitles) with Earlier / Later,
/// the next episode (found from the series when it was not given), the episode strip, the credits cue with the compact
/// end card, and the "Still watching?" toast. The same rules as the Apple TV player (docs/DESIGN.md "Player (2026-10-25)").
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
    /// The account's only stream is used by another device: waiting for it, checked every 5 s for 2 minutes.
    @Published var busy = false
    @Published var attempts = 0
    /// The compact card bottom right once the credits start (rule 4); nil when it is not shown.
    @Published var card: EndCard? = nil
    /// "Still watching?" (rule 6); nil when it is not shown.
    @Published var still: StillAsk? = nil
    /// The series' seasons and episodes (for the Episodes strip and "n of m").
    @Published var seasons: [String] = []
    @Published var episodes: [String: [Episode]] = [:]
    @Published var seriesPoster = ""
    @Published var stripOpen = false
    @Published var stripSeason = ""
    @Published var stripSel = 0
    /// Opened by a click on Episodes: it stays until a second click or Esc (hover alone closes it again).
    @Published var stripPinned = false
    /// The Audio or Subtitles popup over the bar.
    @Published var popup: PlayerPopup? = nil
    /// The clock passed the credits cue (rule 5): "Next episode" shows in the bar.
    @Published private(set) var creditsReached = false
    /// Seconds from the start of the episode where its credits begin (rule 5); nil until the length is known.
    @Published private(set) var creditsAt: Double? = nil
    /// Earlier / Later pressed by hand on the online subtitle, on top of the found timing.
    @Published private(set) var manualShiftMs = 0
    @Published var online: [OSResult] = []
    @Published var onlineState = ""
    @Published var onlineActive: Int? = nil
    @Published var onlineTrack: Int? = nil
    @Published var message: String? = nil
    private var onlineFor = ""
    private var onlineFiles: [Int: URL] = [:]
    private var cardTask: Task<Void, Never>?
    private var stillTask: Task<Void, Never>?
    private var cardDismissed = false
    private var cueStarts: [Double] = []
    private var cueFromSubtitles = false
    private var lastInteractionMs: Int?
    /// The counters of this session (rules 4 and 6).
    private(set) var auto = AutoplayState()
    let credits = CreditsMemory.shared
    private var retryPending = false
    private var lastSave = Date.distantPast
    private var catalog: Catalog!
    private var user: UserStore!
    private var languages: [String] = []
    private var subs: Set<AnyCancellable> = []
    /// Called when the window should close (the end of the last episode or a film).
    var onEnd: (() -> Void)?
    static let ringSecs = 10, stillSecs = 60

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
        if !again { attempts = 0; reconnecting = false; resetEpisode() }
        autoSync.stop()      // a new stream: its own reference
        if onlineFor != item.key { online = []; onlineState = ""; onlineActive = nil; onlineTrack = nil; onlineFiles = [:] } else { onlineTrack = nil }
        vlc.preferredAudio = user.trackPref(item)?.audioLang
        vlc.play(url, startMs: startMs, live: isLive)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "NXMute") { vlc.player.audio?.isMuted = true }     // checks that run while the owner works
        #endif
        if !isLive { user.setResume(item, posMs: startMs, durMs: 0) }
        lastSave = Date()
        if item.kind == .episode { Task { await loadSeries() } }
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

    func stop() { saveResume(); hideCard(); stillTask?.cancel(); vlc.stop() }

    /// The stream stopped: reopen it (live: the live edge; films: the last position), 1, 2, 4, 8, 16 s apart.
    func troubled() {
        guard !retryPending else { return }
        attempts += 1
        if attempts > 5 { vlc.stop(); vlc.failed = true; reconnecting = false; return }
        reconnecting = true; retryPending = true
        let at = isLive ? 0 : max(vlc.timeMs, startMs)
        saveResume()
        vlc.stop()
        // live: at least 3 s, or the provider still counts the old stream and refuses the new one
        let delay = UInt64(isLive ? max(3, 1 << (attempts - 1)) : 1 << (attempts - 1))
        Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            if await catalog.accountFull() == true {
                busy = true; attempts = max(0, attempts - 1)
                var free = false
                for _ in 0..<24 where reconnecting {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if await catalog.accountFull() != true { free = true; break }
                }
                busy = false
                if !free { reconnecting = false; retryPending = false; vlc.failed = true; show("Still in use on another device. Try again later."); return }
            }
            retryPending = false
            guard reconnecting else { return }
            startMs = at
            start(again: true)
        }
    }

    /// A seek by the user (the arrows or the timeline): it also counts as the last interaction (rule 5a) and as a seek (rule 4).
    func seek(by ms: Int) { seek(toMs: vlc.timeMs + ms) }
    func seek(toMs ms: Int) {
        auto.key(); auto.seeked(); lastInteractionMs = vlc.timeMs
        vlc.seek(toMs: ms)
    }
    /// Any key press in the player window (rules 4, 5a and 6): the ring stops, the counters restart.
    func keyPressed() {
        auto.key(); lastInteractionMs = vlc.timeMs
        if card?.ring != nil { cardTask?.cancel(); card?.ring = nil }
    }
    func mouseMoved() { auto.mouse() }

    func zap(_ d: Int) {
        guard isLive, !list.isEmpty else { return }
        index = (index + d + list.count) % list.count
        item = list[index]
        start()
    }

    func tick() {
        guard !isLive, vlc.timeMs > 0 else { return }
        if Date().timeIntervalSince(lastSave) >= 15 { lastSave = Date(); user.setResume(item, posMs: vlc.timeMs, durMs: vlc.lengthMs) }
        creditsCheck()
    }

    func saveResume() {
        guard !isLive, !vlc.ended, vlc.started else { return }
        user.setResume(item, posMs: vlc.timeMs, durMs: vlc.lengthMs)
    }

    /// The end of a film or episode. An episode whose card is up (or was dismissed with Back) stays on the card with no timer;
    /// otherwise the next episode plays, or the window closes.
    func finished() -> Bool {
        if !isLive { user.finished(item); WatchedStore.shared.mark(item) }
        if item.kind == .episode, let sid = item.seriesId, vlc.lengthMs > 0 { recordEndSample(sid) }
        if item.kind == .episode, card != nil || cardDismissed || (next.isEmpty && hasCardKind) {
            cardTask?.cancel()
            if card == nil { showCard(timer: false) } else { card?.ring = nil }
            return true
        }
        if !next.isEmpty { playNext(autoplayed: true); return true }
        return false
    }

    /// The next episode plays: from Next episode or the card (a key or a click, `autoplayed` false) or by itself (rule 6 counts those).
    func playNext(autoplayed: Bool = false) {
        guard let n = next.first else { return }
        if !autoplayed, item.kind == .episode, let sid = item.seriesId { recordPressSample(sid) }
        if !autoplayed { WatchedStore.shared.markIfNearEnd(item, posMs: vlc.timeMs, durMs: vlc.lengthMs) }
        saveResume()
        let rest = Array(next.dropFirst())
        open(n, startMs: user.resumePoint(n)?.posMs ?? 0, next: rest, autoplayed: autoplayed)
    }

    /// Plays one episode of the strip (resume position when it has one); the episodes after it follow.
    func play(episode e: Episode, season: String) {
        closeStrip()
        saveResume()
        let it = episodeItem(e, season: season)
        open(it, startMs: user.resumePoint(it)?.posMs ?? 0, next: followers(of: e, in: season), autoplayed: false)
    }

    private func open(_ it: MediaItem, startMs ms: Int, next rest: [MediaItem], autoplayed: Bool) {
        hideCard(); still = nil; stillTask?.cancel()
        item = it; startMs = ms; next = rest
        start()
        if auto.episodeStarted(autoplayed: autoplayed, windowKey: NSApp.isActive && NSApp.keyWindow != nil) { askStill() }
    }

    /// The series' seasons and episodes; when the player was started from Continue watching or a search, the episodes that
    /// follow come from here too.
    private func loadSeries() async {
        guard let sid = item.seriesId, let d = await catalog.details(MediaItem(kind: .series, id: sid, name: item.seriesName ?? "")) else { return }
        seasons = d.seasons; episodes = d.episodes
        seriesPoster = d.poster
        let title = item.seriesName ?? d.name
        seriesTitle = title
        if let se = PlayerFormat.seasonEpisode(item.name) { stripSeason = se.season }
        guard next.isEmpty else { return }
        let all = d.seasons.flatMap { s in (d.episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == item.id }) else { return }
        next = all.dropFirst(i + 1).map { s, e in episodeItem(e, season: s) }
    }
    private var seriesTitle = ""

    func episodeItem(_ e: Episode, season s: String) -> MediaItem {
        let title = seriesTitle.isEmpty ? (item.seriesName ?? "") : seriesTitle
        return MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s) E\(e.num)", img: e.still.isEmpty ? seriesPoster : e.still, ext: e.ext, sub: e.title,
                         seriesId: item.seriesId, seriesName: title)
    }
    private func followers(of e: Episode, in season: String) -> [MediaItem] {
        let all = seasons.flatMap { s in (episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == e.id }) else { return [] }
        return all.dropFirst(i + 1).map { episodeItem($0.1, season: $0.0) }
    }

    /// The playing episode: its season and its place in it ("3 of 8").
    var place: (season: String, n: Int, of: Int)? {
        guard item.kind == .episode, let se = PlayerFormat.seasonEpisode(item.name), let list = episodes[se.season],
              let i = list.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (se.season, i + 1, list.count)
    }

    // MARK: the Episodes strip (rule 3)

    enum StripCard: Equatable {
        case episode(Episode, MediaItem)
        case season(String, count: Int, next: Bool)
    }
    /// The cards of the open season, with a card for the season before and the one after.
    var stripCards: [StripCard] {
        guard let list = episodes[stripSeason] else { return [] }
        var out: [StripCard] = []
        if let i = seasons.firstIndex(of: stripSeason), i > 0 { out.append(.season(seasons[i - 1], count: episodes[seasons[i - 1]]?.count ?? 0, next: false)) }
        out += list.map { .episode($0, episodeItem($0, season: stripSeason)) }
        if let i = seasons.firstIndex(of: stripSeason), i + 1 < seasons.count { out.append(.season(seasons[i + 1], count: episodes[seasons[i + 1]]?.count ?? 0, next: true)) }
        return out
    }
    func openStrip() {
        guard item.kind == .episode, !episodes.isEmpty else { return }
        if !stripOpen, let p = place { stripSeason = p.season }
        stripOpen = true
        stripSel = stripCards.firstIndex { if case .episode(let e, _) = $0 { return e.id == item.id }; return false } ?? 0
    }
    func closeStrip() { stripOpen = false; stripPinned = false }
    func stripMove(_ d: Int) { stripSel = max(0, min(stripCards.count - 1, stripSel + d)) }
    /// Return or a click on a card: an episode plays; a season card opens that season.
    func stripPick(_ i: Int) {
        let cards = stripCards
        guard cards.indices.contains(i) else { return }
        switch cards[i] {
        case .episode(let e, _): play(episode: e, season: stripSeason)
        case .season(let s, _, let nextOne):
            stripSeason = s
            let c = stripCards
            let eps = c.indices.filter { if case .episode = c[$0] { return true }; return false }
            stripSel = (nextOne ? eps.first : eps.last) ?? 0
        }
    }

    // MARK: the credits cue and the end card (rules 4 and 5)

    struct EndCard: Equatable {
        enum Kind: Equatable { case episode(MediaItem), season(MediaItem, String), home }
        var kind: Kind
        /// Seconds left on the ring; nil = no timer.
        var ring: Int?
    }

    private var hasCardKind: Bool { item.kind == .episode && !isLive }

    private func resetEpisode() {
        hideCard(); cardDismissed = false
        creditsAt = nil; cueStarts = []; cueFromSubtitles = false; lastInteractionMs = nil
        creditsReached = false; stripOpen = false; stripPinned = false; popup = nil
    }

    /// Computes the cue once the length is known, and shows the card when the clock passes it.
    private func creditsCheck() {
        guard item.kind == .episode, vlc.started, vlc.lengthMs > 60_000 else { return }
        let dur = Double(vlc.lengthMs) / 1000
        if creditsAt == nil {
            let remembered = item.seriesId.flatMap { credits.median($0) } != nil
            cueFromSubtitles = !remembered && Credits.quietPoint(cueStarts: shiftedCues, duration: dur) != nil
            creditsAt = creditsCue(for: item.seriesId, duration: dur, memory: credits, cueStarts: shiftedCues)
        }
        guard let at = creditsAt else { return }
        let now = Double(vlc.timeMs) / 1000
        creditsReached = now >= at
        if card != nil || cardDismissed {
            // back before the credits (a seek): the card leaves and may come again
            if now < at - 5 && !vlc.ended { hideCard(); cardDismissed = false }
            return
        }
        if now >= at { showCard(timer: true) }
    }
    private var shiftedCues: [Double] { cueStarts.map { $0 + Double(vlc.subtitleDelayMs) / 1000 } }

    private func showCard(timer: Bool) {
        let kind: EndCard.Kind
        if let n = next.first { kind = .episode(n) }
        else if let i = seasons.firstIndex(of: PlayerFormat.seasonEpisode(item.name)?.season ?? ""), i + 1 < seasons.count,
                let first = episodes[seasons[i + 1]]?.first {
            kind = .season(episodeItem(first, season: seasons[i + 1]), seasons[i + 1])
        } else { kind = .home }
        let ringRuns = auto.cardReached()
        var isEpisode = false
        if case .episode = kind { isEpisode = true }
        card = EndCard(kind: kind, ring: timer && ringRuns && isEpisode ? Self.ringSecs : nil)
        guard card?.ring != nil else { return }
        cardTask?.cancel()
        cardTask = Task {
            while !Task.isCancelled, let r = card?.ring, r > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                card?.ring = r - 1
            }
            if !Task.isCancelled, card?.ring == 0 { playNext(autoplayed: true) }
        }
    }
    func hideCard() { cardTask?.cancel(); cardTask = nil; card = nil }
    /// Back on the card: the credits play to the end, then the card returns with no timer.
    func dismissCard() { cardTask?.cancel(); card = nil; cardDismissed = true }
    /// OK or a click on the card.
    func acceptCard() {
        guard let c = card else { return }
        switch c.kind {
        case .episode: playNext()
        case .season(let it, _):
            hideCard(); saveResume()
            let all = seasons.flatMap { s in (episodes[s] ?? []).map { (s, $0) } }
            let rest = all.firstIndex { $0.1.id == it.id }.map { i in all.dropFirst(i + 1).map { episodeItem($0.1, season: $0.0) } } ?? []
            open(it, startMs: 0, next: rest, autoplayed: false)
        case .home: onEnd?()
        }
    }

    /// Rule 5a, the user pressed Next episode or OK on the card within the last 8 minutes: that position is a sample.
    private func recordPressSample(_ sid: String) {
        guard vlc.lengthMs > 0, vlc.timeMs > 0 else { return }
        let left = Double(vlc.lengthMs - vlc.timeMs) / 1000
        if left > 0 && left <= CreditsMemory.window { credits.record(sid, secondsBeforeEnd: left) }
    }
    /// Rule 5a, the file played to its end: the last seek or key press if it was within the last 8 minutes, else the subtitle quiet point.
    private func recordEndSample(_ sid: String) {
        let len = Double(vlc.lengthMs) / 1000
        if let m = lastInteractionMs, len - Double(m) / 1000 <= CreditsMemory.window, len - Double(m) / 1000 > 0 {
            credits.record(sid, secondsBeforeEnd: len - Double(m) / 1000)
        } else if cueFromSubtitles, let at = creditsAt { credits.record(sid, secondsBeforeEnd: len - at) }
    }

    // MARK: still watching (rule 6)

    struct StillAsk: Equatable { var left: Int; var since: Date }

    private func askStill() {
        still = StillAsk(left: Self.stillSecs, since: Date())
        stillTask?.cancel()
        stillTask = Task {
            while !Task.isCancelled, let l = still?.left, l > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                still?.left = l - 1
            }
            if !Task.isCancelled, still?.left == 0 { still = nil; idleStop() }
        }
    }
    /// No answer: the position is kept and the account's only stream goes back to the provider; play reopens it.
    private func idleStop() { saveResume(); vlc.release(); show("Paused: nobody was watching. Press play to continue.") }
    func keepWatching() {
        guard let s = still else { return }
        auto.answered(keep: true, afterSecs: Date().timeIntervalSince(s.since))
        stillTask?.cancel(); still = nil
    }
    func stillBackToHome() { stillTask?.cancel(); still = nil; auto.answered(keep: false, afterSecs: 0); onEnd?() }

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
            manualShiftMs = 0
            cueStarts = SRT.starts(url).map { Double($0) / 1000 }     // rule 5b reads the cues of the parsed file
            if card == nil { creditsAt = nil }
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

    /// Timing "Auto": the hand-made Earlier / Later steps go, the found timing stays.
    func autoTiming() { if manualShiftMs != 0 { shiftDelay(-manualShiftMs) } }
    func shiftDelay(_ ms: Int) {
        guard let fid = onlineActive else { return }
        manualShiftMs += ms
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

// MARK: - Track rows for the Audio and Subtitles popups

extension VLCController {
    /// The audio or text tracks of the playing file with what VLC knows about each: tag, title, channels, codec.
    func trackInputs(audio: Bool, list: [(Int, String)]) -> [TrackInput] {
        let type = audio ? VLCMediaTracksInformationTypeAudio : VLCMediaTracksInformationTypeText
        let info = (player.media?.tracksInformation as? [[String: Any]] ?? []).filter { ($0[VLCMediaTracksInformationType] as? String) == type }
        return list.filter { $0.0 >= 0 }.map { t in
            let i = info.first { ($0[VLCMediaTracksInformationId] as? NSNumber)?.intValue == t.0 }
            var tag = (i?[VLCMediaTracksInformationLanguage] as? String).flatMap { Self.languageName($0) }
            if tag == nil, !audio { tag = Self.languageName(Self.trackName(t.1).trimmingCharacters(in: .whitespaces)) }
            let title = i?[VLCMediaTracksInformationDescription] as? String
            return TrackInput(id: t.0, raw: t.1, language: tag, title: title,
                              channels: audio ? (i?[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue : nil,
                              codec: audio ? audioFormat(t.0) : nil)
        }
    }
}

/// Episodes the owner finished, kept here because the shared resume store forgets an episode once it is over.
@MainActor
final class WatchedStore {
    static let shared = WatchedStore()
    private let key = "nx.watchedEpisodes"
    private var keys: Set<String>
    init() { keys = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    func isWatched(_ it: MediaItem) -> Bool { keys.contains(it.key) }
    func mark(_ it: MediaItem) {
        guard it.kind == .episode, keys.insert(it.key).inserted else { return }
        UserDefaults.standard.set(Array(keys.suffix(3000)), forKey: key)
    }
    /// Next episode pressed in the last 8 minutes: the episode counts as watched.
    func markIfNearEnd(_ it: MediaItem, posMs: Int, durMs: Int) {
        if durMs > 0, durMs - posMs <= 480_000 { mark(it) }
    }
}
