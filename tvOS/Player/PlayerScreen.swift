import SwiftUI
import TVVLCKit

struct VLCVideoView: UIViewRepresentable {
    let controller: VLCController
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        controller.player.drawable = v
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Full-screen player; all app chrome is hidden behind it.
/// Films and episodes (player redesign 2026-10-25): swipe ← → scrubs the timeline (the frame at the marker shows while
/// paused; click or a short pause jumps there, Menu cancels); click opens the bar: 10 s back, play/pause, 10 s forward,
/// Audio <language>, Subtitles <language>; on the right Next episode (once the credits cue is reached) and Episodes n of m.
/// Focusing Episodes slides the episode strip up. Near the credits a compact card offers the next episode.
/// Live: swipe ↑ ↓ changes channel; the info bar shows the channel and LIVE.
struct PlayerScreen: View {
    @State var request: PlayRequest
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vlc = VLCController()
    @ObservedObject private var toaster = Toaster.shared
    @ObservedObject private var osub = OpenSubtitles.shared
    // online subtitles for this item: results, state, the one playing (its track index in VLC) and downloaded files
    @State private var online: [OSResult] = []
    @State private var onlineState = ""           // "" not searched, "loading", "done", or an error message
    @State private var onlineFor = ""
    @State private var onlineActive: Int? = nil   // file id
    @State private var onlineTrack: Int? = nil    // its subtitle track index
    @State private var onlineFiles: [Int: URL] = [:]
    /// Live realignment of an online subtitle not made for this exact file (Shared/Core/SubAutoSync.swift).
    @State private var autoSync: SubAutoSync?
    @State private var delayTick = 0              // redraws the timing line after Earlier / Later
    /// How the tracks read in the bar and in the popups (Shared/Player/VLCController.swift, TrackLabels); refreshed when tracks change.
    @State private var audioLbl: [Int: TrackLabel] = [:]
    @State private var subLbl: [Int: TrackLabel] = [:]
    @State private var contentH: CGFloat = 400    // height of the open popup's rows

    @State private var infoVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var controls = false
    @State private var picker: TrackKind? = nil
    @State private var scrubMs: Int? = nil
    @State private var scrubFrom = 0
    @State private var scrubTask: Task<Void, Never>?
    @State private var seekTask: Task<Void, Never>?
    @State private var lastPress = Date.distantPast
    @State private var streak = 0
    @State private var lastSave = Date.distantPast
    @State private var attempts = 0
    @State private var reconnecting = false
    @State private var busy = false             // the account's only stream is used by another device
    @State private var retryPending = false    // a reopen is scheduled: further trouble waits for it
    @State private var backgrounded = false
    @Environment(\.scenePhase) private var phase
    @FocusState private var rootFocus: Bool
    @FocusState private var controlFocus: String?
    @FocusState private var trackFocus: Int?
    // the series of the playing episode: the strip, the episodes that follow, the end card
    @State private var series: Details?
    @State private var stripShown = false
    @State private var stripClosedAt = Date.distantPast   // closed with Up or Back: focus landing on Episodes just after does not reopen it
    @State private var stripSeason = ""
    @FocusState private var stripFocus: Int?
    // credits cue and end card (rules in Shared/Core/Stores.swift, CreditsCue)
    @State private var cueStarts: [Int]? = nil    // start times of the subtitle cues: the file's own track, or the online file
    @State private var cueLoading = false
    @State private var cueReached = false
    @State private var reachedAt = 0
    @State private var endCard = false
    @State private var endLeft = 0                // seconds on the ring; the ring runs only while `endRing`
    @State private var endRing = false
    @State private var endDismissed = false       // Back: the credits play on; the card returns at the end, without a ring
    @State private var endTask: Task<Void, Never>?
    @State private var seeked = false             // this episode was sought in (scrub or ±10 s)
    @State private var chainClean = false         // the previous episode of this session reached its card without a seek
    @State private var cleanHere = false
    @State private var autoplayStart = false      // this episode started by itself
    @State private var lastInteractMs: Int? = nil
    @FocusState private var upFocus: Bool
    // "Still watching?"
    @State private var stillLeft = 0
    @State private var stillShownAt = Date()
    @State private var stillTask: Task<Void, Never>?
    @FocusState private var stillFocus: Int?
    static let ringSeconds = 10
    /// 60 s; the simulator tests shorten it with -NXStillSeconds.
    static var stillSeconds: Int { let v = UserDefaults.standard.integer(forKey: "NXStillSeconds"); return v > 0 ? v : 60 }

    enum TrackKind { case audio, subtitles }
    private var isLive: Bool { request.item.kind == .live }
    private var isEpisode: Bool { request.item.kind == .episode }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // the video layer takes the remote while no control has focus (controls are siblings, so clicks reach them)
            ZStack {
                Color.black
                VLCVideoView(controller: vlc)
            }
            .focusable(!controls && picker == nil && !endCard && stillLeft == 0)
            .focused($rootFocus)
            .onMoveCommand { d in move(d) }
            .onTapGesture { select() }
            if !vlc.started && !vlc.failed && !reconnecting { loadingCard }
            if busy {
                VStack(spacing: 10) {
                    HStack(spacing: 14) { Spinner().scaleEffect(0.6).frame(width: 30, height: 30); Text("Your account is in use on another device").font(.ui(30, .semibold)) }
                    Text("Nexus TV starts as soon as it is free").font(.ui(24)).foregroundStyle(.white.opacity(0.65))
                }
                .padding(.horizontal, 40).padding(.vertical, 26).background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.75)))
            } else if reconnecting {
                HStack(spacing: 14) { Spinner().scaleEffect(0.6).frame(width: 30, height: 30); Text("Reconnecting…  \(attempts)/5").font(.ui(24, .semibold)) }
                    .padding(.horizontal, 26).padding(.vertical, 16)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, Theme.x0).padding(.top, 70)
            }
            if vlc.failed { Toast(text: "This could not be played").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if vlc.started {
                Group { if isLive { info } else { vodInfo } }
                    .opacity(infoVisible || controls || scrubMs != nil || picker != nil || stripShown || (vlc.paused && !isLive) ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: infoVisible)
            }
            if let picker { trackPanel(picker) }
            if endCard { endCardView }
            if stillLeft > 0 { stillToast }
            if let t = toaster.text {
                Toast(text: t).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 80).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear { rootFocus = true; start() }
        .onDisappear { saveResume(); vlc.stop(); endTask?.cancel(); stillTask?.cancel() }
        .onExitCommand { back() }
        .onPlayPauseCommand { key(); if !isLive { vlc.toggle(); showInfo() } }
        .onChange(of: vlc.ended) { _, e in if e { finished() } }
        // learn whether this title has subtitles (one file at a time: the account allows a single stream)
        .onChange(of: vlc.started) { _, st in
            guard st else { return }
            Metrics.shared.mark("player.playing")
            reconnecting = false
            let a = attempts
            Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if vlc.started && attempts == a { attempts = 0 } }
            guard !isLive else { return }
            if autoplayStart {      // "Still watching?" is asked at the start of an episode that played by itself
                autoplayStart = false
                user.watching.autoplayed()
                if user.watching.shouldAsk(now: Date()) { showStill() }
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                user.learnSubs(request.item, vlc.subtitleTracks.contains { $0.0 >= 0 })
                applyTrackPrefs()
                refreshLabels()
            }
        }
        .onChange(of: vlc.trouble) { _, _ in troubled() }
        // in the background the single connection is given back (the Frame can use it); it reopens on return
        .onChange(of: phase) { _, p in
            if p == .background && !backgrounded {
                backgrounded = true
                Metrics.shared.mark("player.background: stream stopped")
                saveResume()
                if !isLive { request.startMs = vlc.timeMs }
                vlc.stop()
            } else if p == .active && backgrounded {
                backgrounded = false
                start()
            }
        }
        .onChange(of: vlc.timeMs) { _, _ in periodicSave(); cueCheck() }
        .onChange(of: controlFocus) { old, f in
            if controls { showInfo(long: true) }
            // focusing Episodes (not pressing it) slides the strip up; focus coming back after Up or Back closed it does not
            if f == "episodes" { if old != nil && Date().timeIntervalSince(stripClosedAt) > 0.8 { stripShown = true } }
            else if f != nil, stripFocus == nil { stripShown = false }
        }
        .onChange(of: stripFocus) { _, f in if f != nil { stripShown = true; showInfo(long: true) } }
        .onChange(of: stripShown) { _, s in if s { stripSeason = currentRef?.season ?? series?.seasons.first ?? "" } }
    }

    // MARK: input

    /// Any remote key: it counts for "Still watching?", it is where the owner last interacted (credits sample),
    /// and it stops the ring of the end card (the card stays).
    private func key() {
        user.noteKey()
        lastInteractMs = vlc.timeMs
        if endCard && endRing { endRing = false; endTask?.cancel(); endLeft = 0 }
    }

    private func move(_ d: MoveCommandDirection) {
        key()
        if isLive {
            switch d {
            case .up: zap(-1)
            case .down: zap(1)
            default: showInfo()
            }
            return
        }
        switch d {
        case .left: scrub(-1)
        case .right: scrub(1)
        default: showInfo()
        }
    }

    private func select() {
        key()
        if isLive { showInfo(); return }
        if scrubMs != nil { commitScrub(); return }
        controls = true
        controlFocus = "play"
        showInfo(long: true)
    }

    private func back() {
        key()
        if stillLeft > 0 { answerStill(keep: true); return }
        if endCard { dismissEnd(); return }
        if stripShown || stripFocus != nil { closeStrip(); return }
        if let p = picker { picker = nil; controlFocus = p == .audio ? "audio" : "subs"; return }
        if let _ = scrubMs { cancelScrub(); return }
        if controls { controls = false; rootFocus = true; showInfo(); return }
        close()
    }

    /// Back or Up in the strip: it closes and focus returns to the Episodes button.
    private func closeStrip() {
        stripClosedAt = Date(); stripShown = false; stripFocus = nil
        controlFocus = "episodes"
    }

    // MARK: scrubbing (Apple style)

    /// Each swipe moves the marker; quick repeated swipes move it further each time.
    private func scrub(_ dir: Int) {
        guard vlc.lengthMs > 0 || vlc.timeMs > 0 else { return }
        let now = Date()
        streak = now.timeIntervalSince(lastPress) < 0.5 ? min(streak + 1, 6) : 0
        lastPress = now
        let steps = [10, 10, 20, 30, 60, 120, 300]
        if scrubMs == nil { scrubFrom = vlc.timeMs; scrubMs = vlc.timeMs; vlc.pause() }
        let len = vlc.lengthMs > 0 ? vlc.lengthMs : Int.max
        withAnimation(.easeOut(duration: 0.18)) { scrubMs = min(max(0, (scrubMs ?? 0) + dir * steps[streak] * 1000), len - 1000) }
        // the real frame at the marker: seek while paused, a moment after the last swipe
        seekTask?.cancel()
        let target = scrubMs ?? 0
        seekTask = Task { try? await Task.sleep(nanoseconds: 220_000_000); if !Task.isCancelled { vlc.seek(toMs: target) } }
        // a short pause jumps there and plays
        scrubTask?.cancel()
        scrubTask = Task { try? await Task.sleep(nanoseconds: 1_500_000_000); if !Task.isCancelled { commitScrub() } }
        showInfo(long: true)
    }

    private func commitScrub() {
        guard let t = scrubMs else { return }
        scrubTask?.cancel(); seekTask?.cancel()
        vlc.seek(toMs: t)
        seeked = true; lastInteractMs = t
        scrubMs = nil
        vlc.resume()
        showInfo()
    }

    private func cancelScrub() {
        scrubTask?.cancel(); seekTask?.cancel()
        vlc.seek(toMs: scrubFrom)
        scrubMs = nil
        vlc.resume()
        showInfo()
    }

    // MARK: overlays

    private var loadingCard: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: Img.url(request.picture, .backdrop), maxPixel: 1920, mode: .fill) { Color.black }
                .frame(width: 1920, height: 1080).clipped().opacity(0.35)
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 18) {
                Text(request.item.name).font(.ui(52, .bold)).lineLimit(1)
                Text(isLive ? "Tuning in  \(vlc.loadPct)%" : (request.startMs > 0 ? "Resuming at \(fmtTime(request.startMs))  ·  \(vlc.loadPct)%" : "Loading  \(vlc.loadPct)%"))
                    .font(.ui(26)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white).frame(width: 600 * CGFloat(max(4, vlc.loadPct)) / 100)
                }
                .frame(width: 600, height: 6)
                .animation(.linear(duration: 0.25), value: vlc.loadPct)
            }
            .padding(.leading, Theme.x0).padding(.bottom, 120)
        }
    }


    private var shownMs: Int { scrubMs ?? vlc.timeMs }

    /// Live: the channel and LIVE at the bottom (unchanged).
    private var info: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).frame(height: 320)
            VStack(alignment: .leading, spacing: 10) {
                Text(request.item.name).font(.ui(44, .bold)).lineLimit(1)
                HStack(spacing: 12) {
                    LivePill()
                    Text(request.subtitle.isEmpty ? request.item.sub : request.subtitle).font(.ui(24)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, Theme.x0).padding(.bottom, 50)
        }
        .frame(width: 1920)
    }

    // MARK: films and episodes

    /// "E3" and the season of the playing episode, from its name ("House Of Guinness · S1 E3").
    private func numbers(_ it: MediaItem) -> (season: String, ep: Int)? {
        guard let m = it.name.range(of: "S(\\d+) E(\\d+)$", options: .regularExpression) else { return nil }
        let n = it.name[m].dropFirst().split(separator: " ").map { Int($0.filter(\.isNumber)) ?? 0 }
        return n.count == 2 ? (String(n[0]), n[1]) : nil
    }
    private var episodeTitle: String { request.item.sub.isEmpty ? (currentRef?.ep.title ?? request.subtitle) : request.item.sub }

    /// Top left: the show and season in small capitals, then "E3 · Black Velvet" (a film: its name).
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEpisode, let n = numbers(request.item) {
                Text("\(request.item.seriesName ?? "") · Season \(n.season)").textCase(.uppercase).font(.ui(24)).tracking(0.5).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Text(episodeTitle.isEmpty ? "E\(n.ep)" : "E\(n.ep) · \(episodeTitle)").font(.ui(44, .bold)).lineLimit(1)
            } else {
                Text(request.item.name).font(.ui(44, .bold)).lineLimit(1)
                let sub = request.subtitle.isEmpty ? request.item.sub : request.subtitle
                if !sub.isEmpty { Text(sub).font(.ui(24)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
            }
        }
    }

    /// The bar at the bottom (buttons, timeline, times) and the header at the top; the strip rises under the bar.
    private var vodInfo: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 280)
            if scrubMs == nil { header.padding(.leading, Theme.x0).padding(.top, 64).frame(width: 1920, alignment: .leading) }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).frame(height: stripShown ? 700 : (controls ? 420 : 320))
                    VStack(alignment: .leading, spacing: 18) {
                        if controls { controlBar.disabled(picker != nil) }
                        timeline
                    }
                    .padding(.horizontal, Theme.x0).padding(.bottom, 50)
                    .offset(y: stripShown ? -330 : 0)
                }
                .frame(width: 1920)
            }
            if stripShown && controls {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    episodeStrip.padding(.bottom, 44)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 1920, height: 1080)
        .animation(.easeOut(duration: 0.25), value: stripShown)
    }

    private var timeline: some View {
        let len = max(vlc.lengthMs, 1)
        let width: CGFloat = 1920 - Theme.x0 * 2
        let f = CGFloat(min(1, Double(shownMs) / Double(len)))
        let played = CGFloat(min(1, Double(vlc.timeMs) / Double(len)))
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let s = scrubMs {
                    // card above the marker: target time, large, and the offset from where you were
                    VStack(spacing: 4) {
                        Text(fmtTime(s)).font(.ui(46, .bold)).monospacedDigit()
                        let d = s - scrubFrom
                        Text((d >= 0 ? "+" : "−") + fmtTime(abs(d))).font(.ui(24, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.65)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: 1))
                    .offset(x: min(max(0, width * f - 110), width - 220), y: -34)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22)).frame(height: scrubMs == nil ? 6 : 10)
                    Capsule().fill(Color.white).frame(width: width * played, height: scrubMs == nil ? 6 : 10)
                    if scrubMs == nil { Circle().fill(Color.white).frame(width: 18, height: 18).offset(x: max(0, width * played - 9)) }
                    if scrubMs != nil {
                        Capsule().fill(Color.white).frame(width: 4, height: 34).shadow(color: .black.opacity(0.6), radius: 6)
                            .offset(x: width * f - 2)
                    }
                }
                .frame(width: width, height: 34, alignment: .leading)
            }
            HStack {
                Text(fmtTime(vlc.timeMs)).monospacedDigit()
                Spacer()
                Text(vlc.lengthMs > 0 ? "−" + fmtTime(max(0, vlc.lengthMs - shownMs)) + " · ends " + Self.clock(Date().addingTimeInterval(Double(max(0, vlc.lengthMs - shownMs)) / 1000)) : "").monospacedDigit()
            }
            .font(.ui(22)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    // MARK: the bar

    private var audioShort: String {
        vlc.audioTracks.isEmpty ? "–" : (audioLbl[vlc.audioIndex]?.short ?? "–")
    }
    private var subsShort: String {
        let i = vlc.subtitleIndex
        if i < 0 { return "Off" }
        return subLbl[i]?.short ?? "On"
    }

    /// Round buttons 56 pt; pills 56 pt high with the label at 20 pt semibold and its value at 17 pt, 65 % white.
    private var controlBar: some View {
        HStack(spacing: 14) {
            roundButton("gobackward.10", "Back 10 seconds", "back") { seekBy(-10_000) }
            roundButton(vlc.paused ? "play.fill" : "pause.fill", vlc.paused ? "Play" : "Pause", "play") { vlc.toggle() }
            roundButton("goforward.10", "Forward 10 seconds", "fwd") { seekBy(10_000) }
            pill("speaker.wave.2.fill", "Audio", audioShort, "audio") { openPicker(.audio) }
            pill("captions.bubble", "Subtitles", subsShort, "subs") { openPicker(.subtitles) }
            Spacer(minLength: 0)
            if isEpisode && cueReached && !request.next.isEmpty {
                pill("forward.end.fill", "Next episode", nil, "next") { key(); playNext(pressed: true) }
            }
            if isEpisode && !seasonEps.isEmpty {
                pill("list.bullet", "Episodes", "\(seasonIndex + 1) of \(seasonEps.count)", "episodes") { stripShown = true }
            }
        }
        .frame(width: 1920 - Theme.x0 * 2)
        .focusSection()
    }

    private func seekBy(_ ms: Int) {
        seeked = true; lastInteractMs = vlc.timeMs
        vlc.seek(toMs: vlc.timeMs + ms)
    }

    private func roundButton(_ icon: String, _ name: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button { key(); action() } label: { Image(systemName: icon).font(.ui(24, .semibold)).frame(width: 56) }
            .buttonStyle(PillButtonStyle(height: 56, font: 24, hPad: 0))
            .focused($controlFocus, equals: id)
            .accessibilityLabel(name)
    }

    private func pill(_ icon: String, _ title: String, _ value: String?, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button { key(); action() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.ui(22, .semibold))
                Text(title).font(.ui(20, .semibold))
                if let value { Text(value).font(.ui(17)).opacity(0.65) }
            }
        }
        .buttonStyle(PillButtonStyle(height: 56, font: 20, hPad: 22))
        .focused($controlFocus, equals: id)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "")
    }

    private func openPicker(_ k: TrackKind) {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks
        if (list.isEmpty && !(k == .subtitles && osub.ready)) || (k == .audio && list.count < 2) {
            user.show(k == .audio ? "Only one audio track" : "No subtitles in this file"); return
        }
        refreshLabels()
        picker = k
        if k == .subtitles && osub.ready && onlineFor != request.item.key { Task { await loadOnline() } }
    }

    private func refreshLabels() {
        audioLbl = TrackLabels.labels(vlc.audioFacts, audio: true)
        subLbl = TrackLabels.labels(vlc.subtitleFacts, audio: false)
    }

    // MARK: the episode strip

    private struct EpRef: Identifiable { let season: String; let ep: Episode; var id: String { ep.id } }
    private var allEps: [EpRef] {
        guard let d = series else { return [] }
        return d.seasons.flatMap { s in (d.episodes[s] ?? []).map { EpRef(season: s, ep: $0) } }
    }
    private var currentRef: EpRef? { allEps.first { $0.id == request.item.id } }
    private var seasonEps: [EpRef] { currentRef.map { r in allEps.filter { $0.season == r.season } } ?? [] }
    private var seasonIndex: Int { seasonEps.firstIndex { $0.id == request.item.id } ?? 0 }
    private var stripEps: [EpRef] { allEps.filter { $0.season == stripSeason } }
    private var nextSeason: String? {
        guard let d = series, let i = d.seasons.firstIndex(of: stripSeason), d.seasons.indices.contains(i + 1) else { return nil }
        return d.seasons[i + 1]
    }
    private func epItem(_ r: EpRef) -> MediaItem {
        let title = request.item.seriesName ?? ""
        return MediaItem(kind: .episode, id: r.ep.id, name: "\(title) · S\(r.season) E\(r.ep.num)", img: request.item.img, ext: r.ep.ext, sub: r.ep.title,
                         seriesId: request.item.seriesId, seriesName: title)
    }
    private func itemsAfter(_ r: EpRef) -> [MediaItem] {
        guard let i = allEps.firstIndex(where: { $0.id == r.id }) else { return [] }
        return allEps.dropFirst(i + 1).map(epItem)
    }

    private var episodeStrip: some View {
        let eps = stripEps
        let playing = eps.firstIndex { $0.id == request.item.id }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(eps.enumerated()), id: \.element.id) { i, r in
                        Button { key(); playFromStrip(r) } label: { stripCard(r, index: i, playingIndex: playing) }
                            .buttonStyle(StripCardStyle(playing: i == playing))
                            .focused($stripFocus, equals: i)
                            .disabled(stripFocus == nil && i != playing)      // entering from the bar lands on the playing card only
                            .id(r.id)
                    }
                    if let ns = nextSeason {
                        Button { key(); stripSeason = ns; stripFocus = 0 } label: { seasonCard(ns) }
                            .buttonStyle(StripCardStyle(playing: false))
                            .focused($stripFocus, equals: eps.count)
                            .disabled(stripFocus == nil)
                            .id("next-season")
                    }
                }
                .padding(.horizontal, Theme.x0).padding(.vertical, 10)
            }
            .scrollClipDisabled()
            .onAppear { if let p = playing { proxy.scrollTo(eps[p].id, anchor: .center) } }
            .onChange(of: stripFocus) { _, f in
                guard let f else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f < eps.count ? eps[f].id : "next-season", anchor: .center) }
            }
        }
        .frame(height: 270)
        .focusSection()
        .defaultFocus($stripFocus, playing ?? 0)
        .onMoveCommand { d in if d == .up { key(); closeStrip() } }
    }

    private func stripCard(_ r: EpRef, index: Int, playingIndex: Int?) -> some View {
        let it = epItem(r)
        let isPlaying = index == playingIndex
        let frac: Double = isPlaying ? (vlc.lengthMs > 0 ? Double(vlc.timeMs) / Double(vlc.lengthMs) : 0)
                                     : (user.isWatched(it) ? 1 : (user.resumePoint(it)?.fraction ?? 0))
        let mins = r.ep.durationSecs / 60
        var line2 = isPlaying ? "\(fmtTime(vlc.timeMs)) of \(fmtTime(vlc.lengthMs))" : (mins > 0 ? "\(mins) min" : "")
        if let p = playingIndex { if index == p - 1 { line2 += " · Previous" } else if index == p + 1 { line2 += " · Next" } }
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Theme.tile
                RemoteImage(url: Img.url(r.ep.still.isEmpty ? request.item.img : r.ep.still, .still), maxPixel: 600, mode: .fill) { Theme.tile }
                    .frame(width: 300, height: 168).clipped()
                Rectangle().fill(Color.white.opacity(0.25)).frame(height: 4)
                Rectangle().fill(Color.white).frame(width: 300 * frac, height: 4)
            }
            .frame(width: 300, height: 168)
            .overlay(alignment: .topLeading) {
                if isPlaying || user.isWatched(it) {
                    Text(isPlaying ? "PLAYING" : "WATCHED").font(.ui(13, .bold)).tracking(0.5)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.7)))
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("E\(r.ep.num) · \(r.ep.title)").font(.ui(21, .semibold)).lineLimit(1)
                Text(line2).font(.ui(17)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: 300, height: 77, alignment: .leading).padding(.horizontal, 14).frame(width: 300, alignment: .leading)
            .background(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
        }
        .frame(width: 300)
    }

    private func seasonCard(_ s: String) -> some View {
        let n = series?.episodes[s]?.count ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("Season \(s) ›").font(.ui(24, .semibold))
            Text("\(n) episodes").font(.ui(17)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(16).frame(width: 300, height: 245, alignment: .leading)
        .background(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
    }

    /// OK on a card of the strip: that episode plays (from its resume position, if it has one).
    private func playFromStrip(_ r: EpRef) {
        let it = epItem(r)
        if it.id == request.item.id { closeStrip(); return }
        saveResume()
        request.item = it
        request.subtitle = it.sub
        request.startMs = user.resumePoint(it)?.posMs ?? 0
        request.next = itemsAfter(r)
        chainClean = false
        stripShown = false; stripFocus = nil
        controls = false; rootFocus = true
        start()
    }

    // MARK: online subtitles (OpenSubtitles) and the popups

    private func flagDot(_ asset: String?) -> some View {
        Group {
            if let asset { Image(asset).resizable().interpolation(.high).aspectRatio(contentMode: .fit).clipShape(Circle()) }
            else { Circle().fill(Color.white.opacity(0.22)) }
        }
        .frame(width: 28, height: 28)
    }

    /// One row of a popup: round flag, name, detail in grey on the right.
    private func trackRow(flag: String?, showFlag: Bool = true, name: String, detail: String, label: String? = nil, selected: Bool, width: CGFloat, focus: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if showFlag { flagDot(flag) }
                Text(name).lineLimit(1)
                Spacer(minLength: 12)
                if !detail.isEmpty { Text(detail).font(.ui(18)).opacity(0.6).lineLimit(1) }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(ChipButtonStyle(selected: selected, height: 60, font: 22))
        .accessibilityLabel(label ?? name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .focused($trackFocus, equals: focus)
        .id(focus)
    }

    @ViewBuilder
    private func onlineSection(on: Bool, width: CGFloat) -> some View {
        let _ = delayTick
        Text("ONLINE · OPENSUBTITLES").font(.ui(17, .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
            .accessibilityLabel("Online · OpenSubtitles")
        if onlineState == "loading" || onlineState.isEmpty {
            Text("Searching…").font(.ui(20)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18)
        } else if onlineState != "done" {
            Text(onlineState).font(.ui(20)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18).frame(width: width, alignment: .leading)
        }
        ForEach(Array(online.enumerated()), id: \.element.fileId) { i, r in
            let sel = on && onlineActive == r.fileId
            let lang = OpenSubtitles.languageName(r.lang)
            trackRow(flag: TrackLabels.flag(forLanguage: VLCController.languageName(lang)), name: lang + Self.releaseHint(r.release),
                     detail: r.exact ? "exact file" : (r.hearingImpaired ? "hearing impaired" : ""),
                     label: lang + " · online" + Self.releaseHint(r.release), selected: sel, width: width, focus: 100_000 + i) {
                key(); picker = nil; controlFocus = "subs"
                Task { await pickOnline(r, remember: true) }
            }
        }
    }

    /// Earlier −0.5 s · Auto · Later +0.5 s. An online file keeps its own timing; an embedded track shifts VLC's subtitle delay.
    private func timingRow(online fid: Int?) -> some View {
        let _ = delayTick
        let auto = fid != nil ? (autoSync?.auto ?? 0) : 0
        let isAuto = vlc.subtitleDelayMs == auto
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIMING").font(.ui(17, .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("Timing \(String(format: "%+.1f", Double(vlc.subtitleDelayMs) / 1000)) s").font(.ui(17)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18).padding(.top, 14)
            HStack(spacing: 10) {
                Button { key(); shiftTiming(-500, online: fid) } label: { Text("Earlier −0.5 s").frame(width: 190) }.focused($trackFocus, equals: 99_997)
                Button { key(); setAuto(online: fid) } label: { Text("Auto").frame(width: 120) }.focused($trackFocus, equals: 99_998)
                    .buttonStyle(ChipButtonStyle(selected: isAuto, height: 52, font: 20))
                Button { key(); shiftTiming(500, online: fid) } label: { Text("Later +0.5 s").frame(width: 190) }.focused($trackFocus, equals: 99_999)
            }
            .buttonStyle(ChipButtonStyle(height: 52, font: 20))
            .padding(.leading, 4)
        }
    }

    private func shiftTiming(_ ms: Int, online fid: Int?) {
        if let fid { shiftDelay(fid, ms) } else { vlc.subtitleDelayMs += ms; delayTick += 1 }
    }
    private func setAuto(online fid: Int?) {
        if let fid, let a = autoSync, a.fileId == fid {
            vlc.subtitleDelayMs = a.auto
            var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
            all[String(fid)] = nil
            UserDefaults.standard.set(all, forKey: "nx.subDelay")
        } else { vlc.subtitleDelayMs = 0 }
        delayTick += 1
    }

    /// Audio and subtitles popups: the small menu above the button, a title row, one row per track with its flag.
    private func trackPanel(_ k: TrackKind) -> some View {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks.filter { $0.0 != onlineTrack }
        let labels = k == .audio ? audioLbl : subLbl
        let current = k == .audio ? vlc.audioIndex : vlc.subtitleIndex
        let onlineOn = k == .subtitles && onlineTrack != nil && current == onlineTrack
        let width: CGFloat = k == .audio ? 520 : 600
        return VStack(alignment: .leading, spacing: 6) {
            Text(k == .audio ? "Audio" : "Subtitles").font(.ui(26, .bold)).padding(.horizontal, 18).padding(.bottom, 8)
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(list, id: \.0) { t in
                        let l = labels[t.0]
                        trackRow(flag: l?.flag, showFlag: t.0 >= 0, name: t.0 < 0 ? "Off" : (l?.name ?? Self.trackName(t.1)), detail: l?.detail ?? "",
                                 selected: t.0 == current, width: width, focus: t.0) {
                            key()
                            choose(k, t, in: list)
                            picker = nil; controlFocus = k == .audio ? "audio" : "subs"
                        }
                    }
                    if k == .subtitles && osub.ready { onlineSection(on: onlineOn, width: width) }
                    if k == .subtitles && current >= 0 { timingRow(online: onlineOn ? onlineActive : nil) }
                }
                .padding(4)
                .background(GeometryReader { Color.clear.preference(key: PopupHeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(contentH + 8, 560))
            .onPreferenceChange(PopupHeightKey.self) { contentH = $0 }
            .onAppear {      // opens on the current track, in view
                let f = onlineOn ? (online.firstIndex { $0.fileId == onlineActive }.map { 100_000 + $0 } ?? current) : current
                proxy.scrollTo(f, anchor: .center); trackFocus = f
            }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.stroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, k == .audio ? 400 : 600).padding(.bottom, 200)
        .focusSection()
    }

    /// VLC names tracks like "Track 1 - [English]"; keep the language when there is one.
    static func trackName(_ s: String) -> String {
        if let r = s.range(of: "\\[([^\\]]+)\\]", options: .regularExpression) { return String(s[r].dropFirst().dropLast()) }
        return s
    }

    // MARK: playback

    /// What to search for this item: the film's TMDb id, or the series' TMDb id with season and episode numbers.
    private func onlineQuery() async -> OSQuery? {
        let it = request.item
        if it.kind == .film {
            guard let d = await catalog.details(it), !d.tmdb.isEmpty else { return nil }
            return .film(tmdb: d.tmdb)
        }
        guard it.kind == .episode, let sid = it.seriesId,
              let m = it.name.range(of: "S(\\d+) E(\\d+)$", options: .regularExpression) else { return nil }
        let nums = it.name[m].dropFirst().split(separator: " ").map { Int($0.filter(\.isNumber)) ?? 0 }
        guard nums.count == 2, let d = await catalog.details(MediaItem(kind: .series, id: sid, name: it.seriesName ?? "")), !d.tmdb.isEmpty else { return nil }
        return .episode(seriesTmdb: d.tmdb, season: nums[0], episode: nums[1])
    }

    private func loadOnline() async {
        let key = request.item.key
        onlineFor = key; onlineState = "loading"; online = []
        guard let q = await onlineQuery() else { if onlineFor == key { onlineState = "This title has no TMDb id: no online search." }; return }
        do {
            // the exact-file hash (two small range reads of this stream) and the frame rate rank the results
            let hash = catalog.url(request.item).map { u in Task { await osub.fileHash(u) } }
            let h = await hash?.value ?? ""
            let r = try await osub.search(q, languages: OpenSubtitles.languages(settingsLanguages), hash: h, fps: vlc.fps)
            Metrics.shared.mark("player.osub hash=\(h.isEmpty ? "none" : "ok") fps=\(String(format: "%.3f", vlc.fps)) exact=\(r.filter(\.exact).count)")
            guard onlineFor == key else { return }
            online = r; onlineState = r.isEmpty ? "No online subtitles in your languages." : "done"
            Metrics.shared.mark("player.osub results=\(r.count)")
        } catch {
            if onlineFor == key { onlineState = "Online search failed (\(error.localizedDescription))." }
        }
    }
    /// Manual timing for an online subtitle, kept per subtitle file.
    private func shiftDelay(_ fid: Int, _ ms: Int) {
        if let a = autoSync, a.fileId == fid { _ = a.shift(ms) } else {   // on top of the found offset
            vlc.subtitleDelayMs += ms
            var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
            all[String(fid)] = vlc.subtitleDelayMs
            UserDefaults.standard.set(all, forKey: "nx.subDelay")
        }
        delayTick += 1
        Metrics.shared.mark("player.osub delay=\(vlc.subtitleDelayMs)")
    }
    /// The release a subtitle was made for, short ("· 1080p AMZN"); nothing when the uploader gave no release.
    static func releaseHint(_ release: String) -> String {
        let r = release.replacingOccurrences(of: ".", with: " ")
        guard let m = r.range(of: "\\b((2160p|1080p|720p|480p)\\s+)?(WEB-?DL|WEBRip|WEB|Blu-?Ray|BDRip|BRRip|HDTV|AMZN|NF|DSNP|HMAX|ATVP)\\b", options: [.regularExpression, .caseInsensitive]) else { return "" }
        return " · " + r[m].trimmingCharacters(in: .whitespaces)
    }

    static func savedDelay(_ fid: Int) -> Int { SubAutoSync.savedDelay(fid) }

    private var settingsLanguages: [String] { (UserDefaults.standard.data(forKey: "nx.languages").flatMap { try? JSONDecoder().decode([String].self, from: $0) }) ?? Settings.defaultLanguages }

    /// Downloads (once per file and playback) and shows an online subtitle; with `remember`, the series or film keeps it.
    private func pickOnline(_ r: OSResult, remember: Bool) async {
        do {
            let url: URL
            if let f = onlineFiles[r.fileId] { url = f } else { url = try await osub.download(r); onlineFiles[r.fileId] = url }
            guard let n = await vlc.addSubtitleFile(url) else { user.show("Online subtitles could not be shown"); return }
            onlineActive = r.fileId; onlineTrack = n
            vlc.subtitleDelayMs = Self.savedDelay(r.fileId)
            if remember { user.setTrackPref(request.item) { $0.subOff = false; $0.subOnline = r.lang; $0.subLang = nil; $0.subPos = nil } }
            Metrics.shared.mark("player.osub added lang=\(r.lang) track=\(n) exact=\(r.exact) q=\(r.quality) delay=\(vlc.subtitleDelayMs)")
            await startAutoSync(r, file: url)
        } catch {
            user.show("Online subtitles failed (\(error.localizedDescription))")
        }
    }

    /// Not an exact-file match: align it live against the file's own subtitle track; the next candidates of the same
    /// language (in the ranked order) are tried when this one was timed for another cut.
    private func startAutoSync(_ r: OSResult, file: URL) async {
        guard let stream = catalog.url(request.item) else { return }
        let sync = autoSync ?? SubAutoSync(vlc: vlc)
        autoSync = sync
        let same = online.filter { $0.lang == r.lang }
        let rest = Array(same.drop { $0.fileId != r.fileId }.dropFirst())
        await sync.start(stream: stream, pick: r, file: file, candidates: rest, switchTo: { next in
            do {
                let url: URL
                if let f = onlineFiles[next.fileId] { url = f } else { url = try await osub.download(next); onlineFiles[next.fileId] = url }
                guard let n = await vlc.addSubtitleFile(url) else { return nil }
                onlineActive = next.fileId; onlineTrack = n
                return url
            } catch { return nil }
        }, log: { Metrics.shared.mark($0) })
    }

    /// Saves the owner's track choice for this film / series (language first, position as fallback) and applies it.
    private func choose(_ k: TrackKind, _ t: (Int, String), in list: [(Int, String)]) {
        let pos = list.filter { $0.0 >= 0 }.firstIndex { $0.0 == t.0 }
        let lang = t.0 >= 0 ? Self.trackName(t.1) : nil
        if k == .audio {
            vlc.setAudio(t.0)
            user.setTrackPref(request.item) { $0.audioLang = lang; $0.audioPos = pos }
        } else {
            vlc.setSubtitle(t.0)
            autoSync?.stop()
            user.setTrackPref(request.item) { $0.subOff = t.0 < 0; $0.subLang = lang; $0.subPos = pos; $0.subOnline = nil }
        }
        Metrics.shared.mark("player.choose \(k == .audio ? "audio" : "subs")=\(lang ?? "Off") index=\(t.0)")
        if k == .audio {
            // what VLC really plays a moment later, and whether the clock still moves (audio test)
            let want = t.0, t0 = vlc.timeMs, name = audioLbl[t.0]?.name ?? Self.trackName(t.1)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if vlc.audioIndex != want {          // one retry: VLC can refuse a change while it is still opening the track
                    vlc.setAudio(want)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                Metrics.shared.mark("player.audio-now index=\(vlc.audioIndex) wanted=\(want) clock+\((vlc.timeMs - t0) / 1000)s")
                if vlc.audioIndex != want {
                    let kept = audioLbl[vlc.audioIndex]?.name ?? "no track"
                    user.show("Could not switch to \(name): the player stayed on \(kept)")
                }
            }
        }
    }

    /// Reapplies the saved choice when a film or any episode of the series starts; subtitles are off by default.
    private func applyTrackPrefs() {
        let p = user.trackPref(request.item)
        func pick(_ list: [(Int, String)], lang: String?, pos: Int?) -> Int? {
            let real = list.filter { $0.0 >= 0 }
            if let lang, let m = real.first(where: { Self.trackName($0.1).caseInsensitiveCompare(lang) == .orderedSame }) { return m.0 }
            if let pos, real.indices.contains(pos) { return real[pos].0 }
            return nil
        }
        if let a = pick(vlc.audioTracks, lang: p?.audioLang, pos: p?.audioPos), a != vlc.audioIndex {
            vlc.setAudio(a)
            Task {      // checked once it had time to take; one retry
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if vlc.audioIndex != a { vlc.setAudio(a) }
                Metrics.shared.mark("player.audio-pref index=\(vlc.audioIndex) wanted=\(a)")
            }
        }
        if let lang = p?.subOnline, osub.ready {
            Task {
                if onlineFor != request.item.key || online.isEmpty { await loadOnline() }
                if let r = online.first(where: { $0.lang == lang }) { await pickOnline(r, remember: false); Metrics.shared.mark("player.osub auto lang=\(lang)") }
            }
        } else if p?.subOff ?? true { vlc.setSubtitle(-1) }
        else if let s = pick(vlc.subtitleTracks, lang: p?.subLang, pos: p?.subPos) { vlc.setSubtitle(s) }
        let an = vlc.audioTracks.first { $0.0 == vlc.audioIndex }.map { Self.trackName($0.1) } ?? "-"
        let sn = vlc.subtitleIndex < 0 ? "Off" : (vlc.subtitleTracks.first { $0.0 == vlc.subtitleIndex }.map { Self.trackName($0.1) } ?? "-")
        Metrics.shared.mark("player.tracks \(request.item.name) audio=\(an) subs=\(sn) audioTracks=\(vlc.audioTracks.count)")
    }

    /// The stream stopped: reopen the same URL (live: the live edge; films: the last position), 1, 2, 4, 8, 16 s apart.
    private func troubled() {
        guard !retryPending, !backgrounded else { return }
        attempts += 1
        Metrics.shared.mark("player.trouble \(attempts)")
        if attempts > 5 { vlc.stop(); vlc.failed = true; reconnecting = false; return }
        reconnecting = true
        retryPending = true
        let at = isLive ? 0 : max(vlc.timeMs, request.startMs)
        saveResume()
        vlc.stop()
        // live: at least 3 s, or the provider still counts the old stream and refuses the new one
        let delay = UInt64(isLive ? max(3, 1 << (attempts - 1)) : 1 << (attempts - 1))
        Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            if await catalog.accountFull() == true {
                busy = true; attempts = max(0, attempts - 1)
                var free = false
                for _ in 0..<24 where reconnecting && !backgrounded {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if await catalog.accountFull() != true { free = true; break }
                }
                busy = false
                if !free { reconnecting = false; retryPending = false; vlc.failed = true; user.show("Still in use on another device. Try again later."); return }
            }
            retryPending = false     // a reopen that fails again counts as the next attempt
            guard reconnecting, !backgrounded else { return }
            Metrics.shared.mark("player.reconnect \(attempts)")
            request.startMs = at
            start(again: true)
        }
    }


    private func start(again: Bool = false) {
        guard let url = PlayerDemo.file ?? catalog.url(request.item) else { vlc.failed = true; return }
        if !again {
            attempts = 0; reconnecting = false
            // a new episode: its own credits cue, end card and seek record
            endHide(); cueReached = false; endDismissed = false; seeked = false; cueStarts = nil; cueLoading = false; lastInteractMs = nil
            stripShown = false
        }
        autoSync?.stop()     // a new stream: its own reference
        if onlineFor != request.item.key { online = []; onlineState = ""; onlineActive = nil; onlineTrack = nil; onlineFiles = [:] }
        else { onlineTrack = nil }      // a reopened stream: the remembered choice adds the file again
        vlc.preferredAudio = user.trackPref(request.item)?.audioLang
        vlc.play(url, startMs: request.startMs, live: isLive)
        if !isLive { user.setResume(request.item, posMs: request.startMs, durMs: 0) }   // in Continue watching from the start
        lastSave = Date()
        showInfo()
        if request.item.kind == .episode && series == nil { Task { await loadSeries() } }
        else if request.item.kind == .episode, request.next.isEmpty, let r = currentRef { request.next = itemsAfter(r) }
    }

    private func showInfo(long: Bool = false) {
        infoVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: long ? 7_000_000_000 : 4_000_000_000)
            if !Task.isCancelled && picker == nil && scrubMs == nil && !stripShown && stripFocus == nil {
                infoVisible = false
                if controls { controls = false; rootFocus = true }
            }
        }
    }

    private func zap(_ d: Int) {
        guard !request.list.isEmpty else { showInfo(); return }
        let i = (request.index + d + request.list.count) % request.list.count
        request.index = i
        request.item = request.list[i]
        request.subtitle = request.list[i].sub
        start()                      // play() stops and releases the previous channel first
    }

    private func periodicSave() {
        guard !isLive, scrubMs == nil, Date().timeIntervalSince(lastSave) >= 15, vlc.timeMs > 0 else { return }
        lastSave = Date()
        user.setResume(request.item, posMs: vlc.timeMs, durMs: vlc.lengthMs)
    }

    private func saveResume() {
        guard !isLive, !vlc.ended, vlc.started else { return }
        user.setResume(request.item, posMs: scrubMs ?? vlc.timeMs, durMs: vlc.lengthMs)
    }

    /// The file played to its end. A show with a next episode shows its card (the ring, if it runs, plays the next one);
    /// otherwise the card waits for an answer. A film or a channel closes the player.
    private func finished() {
        guard !isLive else { close(); return }
        user.finished(request.item)
        if let sid = request.item.seriesId, let s = CreditsCue.endSample(lengthMs: vlc.lengthMs, lastInteractionMs: lastInteractMs, quietPointMs: quietPoint()) {
            user.recordCredits(seriesId: sid, secondsBeforeEnd: s)
        }
        guard isEpisode else { close(); return }
        if !endCard { showEnd(allowRing: false) }
    }

    private func playNext(autoplay: Bool = false, pressed: Bool = false) {
        endHide()
        guard let n = request.next.first else { if pressed { close() }; return }
        if pressed, let sid = request.item.seriesId, let s = CreditsCue.pressSample(remainingMs: vlc.lengthMs - vlc.timeMs) {
            user.recordCredits(seriesId: sid, secondsBeforeEnd: s)       // the credits start about here for this show
        }
        saveResume()
        chainClean = cleanHere && (endCard || cueReached)
        autoplayStart = autoplay
        request.item = n
        request.subtitle = n.sub
        request.startMs = user.resumePoint(n)?.posMs ?? 0
        request.next = Array(request.next.dropFirst())
        controls = false; rootFocus = true
        start()
    }

    /// The series of the playing episode: every season (the strip) and the episodes that follow (the end card).
    private func loadSeries() async {
        guard request.item.kind == .episode, let sid = request.item.seriesId else { return }
        let d: Details? = PlayerDemo.on ? PlayerDemo.series() : await catalog.details(MediaItem(kind: .series, id: sid, name: request.item.seriesName ?? ""))
        guard let d else { return }
        series = d
        if request.next.isEmpty, let r = currentRef { request.next = itemsAfter(r) }
    }

    // MARK: credits cue

    /// Start times of the subtitle cues: the online file when one is loaded (no network), else the file's own text track
    /// from its Matroska index, read once, only in the last minutes of an episode that has no memory yet.
    private func loadCueStarts(hasMemory: Bool) {
        guard cueStarts == nil, !cueLoading, !hasMemory, vlc.lengthMs > 0, vlc.lengthMs - vlc.timeMs <= CreditsCue.quietWindowMs + 30_000 else { return }
        if let fid = onlineActive, let f = onlineFiles[fid] { cueStarts = SRT.starts(f); return }
        guard vlc.subtitleTracks.contains(where: { $0.0 >= 0 }), let url = PlayerDemo.file ?? catalog.url(request.item) else { cueStarts = []; return }
        cueLoading = true
        Task { let s = await MatroskaSubIndex.referenceStarts(url); cueStarts = s ?? []; cueLoading = false }
    }

    private func quietPoint() -> Int? {
        guard let c = cueStarts, !c.isEmpty else { return nil }
        return CreditsCue.quietStart(cueStartsMs: c, nowMs: vlc.timeMs, lengthMs: vlc.lengthMs)
    }

    private func cueCheck() {
        guard isEpisode, vlc.started, vlc.lengthMs > 60_000, scrubMs == nil else { return }
        let memory = request.item.seriesId.map { user.creditsMemory(seriesId: $0) } ?? []
        loadCueStarts(hasMemory: !memory.isEmpty)
        let cue = CreditsCue.cueMs(lengthMs: vlc.lengthMs, memorySecondsBeforeEnd: memory, cueStartsMs: cueStarts, nowMs: vlc.timeMs)
        if !cueReached {
            guard vlc.timeMs >= cue, vlc.timeMs > 0 else { return }
            cueReached = true; reachedAt = vlc.timeMs
            Metrics.shared.mark("player.credits cue=\(cue / 1000)s memory=\(memory.count) subs=\(cueStarts?.count ?? -1)")
        } else if vlc.timeMs < reachedAt - 90_000 {      // the owner went back well before the credits
            cueReached = false; endDismissed = false; endHide()
            return
        }
        if !endCard && !endDismissed && picker == nil && !stripShown && stillLeft == 0 { showEnd(allowRing: true) }
    }

    // MARK: end card

    private var nextSeasonStarts: Bool {
        guard let n = request.next.first, let a = numbers(n), let b = numbers(request.item) else { return false }
        return a.season != b.season
    }

    private func showEnd(allowRing: Bool) {
        endCard = true
        controls = false; picker = nil
        cleanHere = !seeked
        endRing = allowRing && chainClean && cleanHere && !request.next.isEmpty && !nextSeasonStarts
        endLeft = endRing ? Self.ringSeconds : 0
        Metrics.shared.mark("player.endcard shown ring=\(endRing) chain=\(chainClean) seeked=\(seeked)")
        DispatchQueue.main.async { upFocus = true }
        endTask?.cancel()
        guard endRing else { return }
        endTask = Task {
            while !Task.isCancelled && endLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                endLeft -= 1
            }
            if !Task.isCancelled && endRing { playNext(autoplay: true) }
        }
    }

    private func endHide() { endTask?.cancel(); endTask = nil; endCard = false; endRing = false; endLeft = 0 }

    /// Back on the card: the credits play on; the card returns at the end of the file, without a ring.
    private func dismissEnd() {
        endHide(); endDismissed = true
        rootFocus = true
        showInfo()
    }

    private func endAction() {
        key()
        if request.next.isEmpty { close() } else { playNext(pressed: true) }
    }

    private var endCardView: some View {
        let n = request.next.first
        let ref = n.flatMap { x in allEps.first { $0.id == x.id } }
        let nn = n.flatMap { numbers($0) }
        let mins = (ref?.ep.durationSecs ?? 0) / 60
        let kicker: String = {
            guard n != nil, let nn else { return "LAST EPISODE" }
            let tag = nextSeasonStarts ? "NEXT SEASON · S\(nn.season) E\(nn.ep)" : "NEXT · E\(nn.ep)"
            return tag + (mins > 0 ? " · \(mins) MIN" : "")
        }()
        let title = n == nil ? "Back to Home" : (n!.sub.isEmpty ? "Episode \(nn?.ep ?? 0)" : n!.sub)
        let foot = n == nil ? "OK goes home · Back keeps the credits" : "OK plays now · Back keeps the credits"
        return Button { endAction() } label: {
            HStack(spacing: 16) {
                RemoteImage(url: Img.url((ref?.ep.still.isEmpty ?? true) ? request.item.img : ref!.ep.still, .still), maxPixel: 400, mode: .fill) { Theme.tile }
                    .frame(width: 150, height: 84).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(kicker).font(.ui(14, .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(title).font(.ui(26, .bold)).lineLimit(1)
                    Text(foot).font(.ui(16)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if endRing {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 4)
                        Circle().trim(from: 0, to: CGFloat(endLeft) / CGFloat(Self.ringSeconds)).stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(endLeft)").font(.ui(22, .bold)).monospacedDigit()
                    }
                    .frame(width: 52, height: 52)
                    .animation(.linear(duration: 1), value: endLeft)
                }
            }
            .padding(12)
            .frame(width: 520)
        }
        .buttonStyle(EndCardStyle())
        .focused($upFocus)
        .accessibilityLabel(n == nil ? "Back to Home" : "Next episode card")
        .onMoveCommand { _ in key() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Theme.x0).padding(.bottom, controls || infoVisible || vlc.paused ? 130 : 60)
        .focusSection()
    }

    // MARK: still watching

    private func showStill() {
        stillShownAt = Date(); stillLeft = Self.stillSeconds
        Metrics.shared.mark("player.stillwatching shown autoplays=\(user.watching.autoplays)")
        DispatchQueue.main.async { stillFocus = 0 }
        stillTask?.cancel()
        stillTask = Task {
            while !Task.isCancelled && stillLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                stillLeft -= 1
            }
            if !Task.isCancelled { stillTimeout() }
        }
    }

    /// No answer in 60 s: pause, keep the position, give the account's only stream back.
    private func stillTimeout() {
        stillLeft = 0
        saveResume()
        vlc.pause(); vlc.release()
        vlc.paused = true; infoVisible = true      // the stream is closed: the header and the timeline stay, play reopens it
        rootFocus = true
        Metrics.shared.mark("player.stillwatching timeout: released")
        user.show("Paused. Press play to continue")
    }

    private func answerStill(keep: Bool) {
        let t = Date().timeIntervalSince(stillShownAt)
        stillTask?.cancel(); stillLeft = 0
        user.noteKey()
        user.watching.answered(keep: keep, after: t, now: Date())
        rootFocus = true
        if !keep { close() }
    }

    private var stillToast: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Still watching?").font(.ui(24, .bold))
            Text("No key press for \(user.watching.threshold) episodes. Playback pauses in \(Self.stillSeconds) s and frees your account's stream for other devices.")
                .font(.ui(17)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { answerStill(keep: true) } label: { Text("Keep watching") }.focused($stillFocus, equals: 0)
                Button { answerStill(keep: false) } label: { Text("Back to Home") }.focused($stillFocus, equals: 1)
                Spacer()
                Text(String(format: "%d:%02d", stillLeft / 60, stillLeft % 60)).font(.ui(17)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(PillButtonStyle(height: 44, font: 18, hPad: 20))
        }
        .padding(18)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Theme.x0).padding(.bottom, 130)
        .focusSection()
    }

    private func close() {
        saveResume()
        vlc.stop()
        dismiss()
    }
}

/// An episode card in the strip: a white 4 pt ring when it is the playing one or has focus.
struct StripCardStyle: ButtonStyle {
    var playing: Bool
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, playing: playing) }
    struct Face: View {
        let configuration: Configuration
        let playing: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white, lineWidth: playing || focused ? 4 : 0).padding(-2))
                .scaleEffect(focused ? 1.05 : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

/// The end card: a compact dark row; a white ring shows that it has focus.
struct EndCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }
    struct Face: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(focused ? Color.white : Theme.stroke, lineWidth: focused ? 3 : 1))
                .scaleEffect(focused ? 1.02 : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

private struct PopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
