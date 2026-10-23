import SwiftUI
import TVVLCKit

/// VLCKit wrapper: plays live HLS and MKV/MP4 files, reports time, state and loading progress.
final class VLCController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    @Published var timeMs = 0
    @Published var lengthMs = 0
    @Published var started = false      // first frames are on screen
    @Published var loadPct = 0          // share of the start-up buffer received (approximate)
    @Published var paused = false
    @Published var failed = false
    @Published var ended = false
    /// The stream stopped moving (error, live end-of-stream, or no progress for 6 s while it should play).
    @Published var trouble = 0
    private var poll: Timer?
    private var lastProgress = Date()
    private var lastTime = -1
    private var ticks = 0
    private var live = false
    private static let startBuffer = 2_500_000   // bytes the start-up progress counts towards

    override init() {
        super.init()
        player.delegate = self
    }

    /// Opens one stream. The account allows a single connection: the previous media is stopped and released first.
    func play(_ url: URL, startMs: Int, live: Bool) {
        stop()
        self.live = live
        failed = false; ended = false; started = false; loadPct = 0; timeMs = startMs; lengthMs = 0; paused = false
        lastProgress = Date(); lastTime = -1
        let m = VLCMedia(url: url)
        m.addOption(live ? ":network-caching=3000" : ":network-caching=5000")
        m.addOption(":http-reconnect")
        m.addOption(":http-user-agent=Mozilla/5.0 (AppleTV) NexusTV/1.0")
        if startMs > 0 { m.addOption(":start-time=\(Double(startMs) / 1000)") }
        player.media = m
        player.play()
        poll?.invalidate()
        Metrics.shared.mark("player.open \(live ? "live" : "file")")
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.started, let media = self.player.media {
                let b = Int(media.statistics.readBytes)
                self.loadPct = min(99, max(self.loadPct, b * 100 / Self.startBuffer))
            }
            self.ticks += 1
            if Metrics.on, self.ticks % 8 == 1 {      // every 2 s: where the clock is (network-cut test)
                Metrics.shared.mark("player.clock \(self.timeMs / 1000)s bytes \(self.player.media?.statistics.readBytes ?? 0)")
            }
            // stall watch: the clock has not moved for 6 s while playing (not paused by the owner),
            // or a stream has not started 15 s after it was opened (a film can take several seconds to open)
            if !self.paused, self.player.media != nil, Date().timeIntervalSince(self.lastProgress) > (self.started ? 6 : 15) {
                self.lastProgress = Date()
                self.trouble += 1
            }
        }
    }

    func stop() {
        poll?.invalidate()
        if player.media != nil { player.stop(); player.media = nil }
    }
    func toggle() { if player.isPlaying { player.pause() } else { player.play() } }
    func pause() { player.pause() }
    func resume() { player.play() }
    func seek(toMs ms: Int) {
        guard player.isSeekable else { return }
        player.time = VLCTime(int: Int32(max(0, ms)))
        timeMs = max(0, ms)
    }

    // Audio and subtitle tracks, as (index, name)
    var audioTracks: [(Int, String)] { zip(player.audioTrackIndexes as? [NSNumber] ?? [], player.audioTrackNames as? [String] ?? []).map { ($0.intValue, $1) }.filter { $0.0 >= 0 } }
    var subtitleTracks: [(Int, String)] { zip(player.videoSubTitlesIndexes as? [NSNumber] ?? [], player.videoSubTitlesNames as? [String] ?? []).map { ($0.intValue, $1) } }
    var audioIndex: Int { Int(player.currentAudioTrackIndex) }
    var subtitleIndex: Int { Int(player.currentVideoSubTitleIndex) }
    func setAudio(_ i: Int) { player.currentAudioTrackIndex = Int32(i) }
    func setSubtitle(_ i: Int) { player.currentVideoSubTitleIndex = Int32(i) }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [self] in
            switch player.state {
            case .playing: paused = false
            case .paused: paused = true
            case .error: trouble += 1
            case .ended:
                // a live stream never ends by itself, and a film that "ends" well before its length lost its connection
                if live || (lengthMs > 0 && timeMs < lengthMs - 60_000) { trouble += 1 } else { ended = true }
            default: break
            }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [self] in
            timeMs = Int(player.time.intValue)
            lengthMs = Int(player.media?.length.intValue ?? 0)
            if timeMs != lastTime { lastTime = timeMs; lastProgress = Date() }
            if player.isPlaying && paused { paused = false }
            if !started && player.isPlaying { started = true; loadPct = 100 }   // the poll keeps running: it is also the stall watch
        }
    }
}

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
/// Films and episodes: swipe ← → scrubs the timeline (the frame at the marker shows while paused, faster when held;
/// click or a short pause jumps there, Menu cancels); click opens the control bar (−10 s, play/pause, +10 s, Audio,
/// Subtitles, Next episode). Live: swipe ↑ ↓ changes channel; the info bar shows the channel and LIVE.
struct PlayerScreen: View {
    @State var request: PlayRequest
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vlc = VLCController()
    @ObservedObject private var toaster = Toaster.shared

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
    @State private var retryPending = false    // a reopen is scheduled: further trouble waits for it
    @State private var backgrounded = false
    @Environment(\.scenePhase) private var phase
    @FocusState private var rootFocus: Bool
    @FocusState private var controlFocus: String?
    @FocusState private var trackFocus: Int?

    enum TrackKind { case audio, subtitles }
    private var isLive: Bool { request.item.kind == .live }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // the video layer takes the remote while no control has focus (controls are siblings, so clicks reach them)
            ZStack {
                Color.black
                VLCVideoView(controller: vlc)
            }
            .focusable(!controls && picker == nil)
            .focused($rootFocus)
            .onMoveCommand { d in move(d) }
            .onTapGesture { select() }
            if !vlc.started && !vlc.failed && !reconnecting { loadingCard }
            if reconnecting {
                HStack(spacing: 14) { Spinner().scaleEffect(0.6).frame(width: 30, height: 30); Text("Reconnecting…  \(attempts)/5").font(.ui(24, .semibold)) }
                    .padding(.horizontal, 26).padding(.vertical, 16)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, Theme.x0).padding(.top, 70)
            }
            if vlc.failed { Toast(text: "This could not be played").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if vlc.started {
                info.opacity(infoVisible || controls || scrubMs != nil || picker != nil || (vlc.paused && !isLive) ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: infoVisible)
            }
            if let picker { trackPanel(picker) }
            if let t = toaster.text {
                Toast(text: t).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 80).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear { rootFocus = true; start() }
        .onDisappear { saveResume(); vlc.stop() }
        .onExitCommand { back() }
        .onPlayPauseCommand { if !isLive { vlc.toggle(); showInfo() } }
        .onChange(of: vlc.ended) { _, e in if e { finished() } }
        // learn whether this title has subtitles (one file at a time: the account allows a single stream)
        .onChange(of: vlc.started) { _, st in
            guard st else { return }
            Metrics.shared.mark("player.playing")
            reconnecting = false
            let a = attempts
            Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if vlc.started && attempts == a { attempts = 0 } }
            guard !isLive else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                user.learnSubs(request.item, vlc.subtitleTracks.contains { $0.0 >= 0 })
                applyTrackPrefs()
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
        .onChange(of: vlc.timeMs) { _, _ in periodicSave() }
        .onChange(of: controlFocus) { _, _ in if controls { showInfo(long: true) } }
    }

    // MARK: input

    private func move(_ d: MoveCommandDirection) {
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
        if isLive { showInfo(); return }
        if scrubMs != nil { commitScrub(); return }
        controls = true
        controlFocus = "play"
        showInfo(long: true)
    }

    private func back() {
        if let p = picker { picker = nil; controlFocus = p == .audio ? "audio" : "subs"; return }
        if let _ = scrubMs { cancelScrub(); return }
        if controls { controls = false; rootFocus = true; showInfo(); return }
        close()
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

    private var info: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).frame(height: controls ? 420 : 320)
            VStack(alignment: .leading, spacing: 10) {
                if scrubMs == nil {
                    Text(request.item.name).font(.ui(44, .bold)).lineLimit(1)
                    HStack(spacing: 12) {
                        if isLive { LivePill() }
                        Text(request.subtitle.isEmpty ? request.item.sub : request.subtitle).font(.ui(24)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        Spacer()
                        if vlc.paused && !isLive { Image(systemName: "pause.fill").font(.ui(24)) }
                    }
                }
                if !isLive { timeline.padding(.top, 14) }
                if controls && !isLive { controlBar.padding(.top, 22).disabled(picker != nil) }   // the open panel holds focus
            }
            .padding(.horizontal, Theme.x0).padding(.bottom, 50)
        }
        .frame(width: 1920)
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
                Text(vlc.lengthMs > 0 ? "−" + fmtTime(max(0, vlc.lengthMs - shownMs)) : "").monospacedDigit()
            }
            .font(.ui(22)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Button { vlc.seek(toMs: vlc.timeMs - 10_000) } label: { Label("10 s", systemImage: "gobackward.10") }
                .focused($controlFocus, equals: "back")
            Button { vlc.toggle() } label: { Image(systemName: vlc.paused ? "play.fill" : "pause.fill").frame(width: 34) }
                .focused($controlFocus, equals: "play")
            Button { vlc.seek(toMs: vlc.timeMs + 10_000) } label: { Label("10 s", systemImage: "goforward.10") }
                .focused($controlFocus, equals: "fwd")
            Button { openPicker(.audio) } label: { Label("Audio", systemImage: "speaker.wave.2") }
                .focused($controlFocus, equals: "audio")
            Button { openPicker(.subtitles) } label: { Label("Subtitles", systemImage: "captions.bubble") }
                .focused($controlFocus, equals: "subs")
            if !request.next.isEmpty {
                Button { playNext() } label: { Label("Next episode", systemImage: "forward.end.fill") }
                    .focused($controlFocus, equals: "next")
            }
        }
        .buttonStyle(PillButtonStyle(height: 56, font: 21, hPad: 22))
        .focusSection()
    }

    private func openPicker(_ k: TrackKind) {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks
        if list.isEmpty || (k == .audio && list.count < 2) {
            user.show(k == .audio ? "Only one audio track" : "No subtitles in this file"); return
        }
        picker = k
    }

    private func trackPanel(_ k: TrackKind) -> some View {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks
        let current = k == .audio ? vlc.audioIndex : vlc.subtitleIndex
        return VStack(alignment: .leading, spacing: 6) {
            Text(k == .audio ? "Audio" : "Subtitles").font(.ui(26, .bold)).padding(.horizontal, 18).padding(.bottom, 8)
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(list, id: \.0) { t in
                        Button {
                            choose(k, t, in: list)
                            picker = nil; controlFocus = k == .audio ? "audio" : "subs"
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "checkmark").opacity(t.0 == current ? 1 : 0).frame(width: 26)
                                Text(t.0 < 0 ? "Off" : Self.label(t, in: list))
                            }
                            .frame(width: 420, alignment: .leading)
                        }
                        .buttonStyle(ChipButtonStyle(selected: t.0 == current, height: 56, font: 22))
                        .accessibilityAddTraits(t.0 == current ? .isSelected : [])
                        .focused($trackFocus, equals: t.0)
                        .id(t.0)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 520)
            .onAppear { proxy.scrollTo(current, anchor: .center); trackFocus = current }   // opens on the current track, in view
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.stroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Theme.x0).padding(.bottom, 200)
        .focusSection()
    }

    /// VLC names tracks like "Track 1 - [English]"; keep the language when there is one.
    /// A track's name in the panel; two tracks with the same language get their number ("English 2").
    static func label(_ t: (Int, String), in list: [(Int, String)]) -> String {
        let n = trackName(t.1).trimmingCharacters(in: .whitespaces)
        let key = { (x: (Int, String)) in trackName(x.1).trimmingCharacters(in: .whitespaces).lowercased() }
        let same = list.filter { $0.0 >= 0 && key($0) == n.lowercased() }
        guard same.count > 1, let i = same.firstIndex(where: { $0.0 == t.0 }) else { return n }
        return "\(n) \(i + 1)"
    }

    static func trackName(_ s: String) -> String {
        if let r = s.range(of: "\\[([^\\]]+)\\]", options: .regularExpression) { return String(s[r].dropFirst().dropLast()) }
        return s
    }

    // MARK: playback

    /// Saves the owner's track choice for this film / series (language first, position as fallback) and applies it.
    private func choose(_ k: TrackKind, _ t: (Int, String), in list: [(Int, String)]) {
        let pos = list.filter { $0.0 >= 0 }.firstIndex { $0.0 == t.0 }
        let lang = t.0 >= 0 ? Self.trackName(t.1) : nil
        if k == .audio {
            vlc.setAudio(t.0)
            user.setTrackPref(request.item) { $0.audioLang = lang; $0.audioPos = pos }
        } else {
            vlc.setSubtitle(t.0)
            user.setTrackPref(request.item) { $0.subOff = t.0 < 0; $0.subLang = lang; $0.subPos = pos }
        }
        Metrics.shared.mark("player.choose \(k == .audio ? "audio" : "subs")=\(lang ?? "Off") index=\(t.0)")
        if k == .audio {
            // what VLC really plays a moment later, and whether the clock still moves (audio test)
            let want = t.0, t0 = vlc.timeMs
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                Metrics.shared.mark("player.audio-now index=\(vlc.audioIndex) wanted=\(want) clock+\((vlc.timeMs - t0) / 1000)s")
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
        if let a = pick(vlc.audioTracks, lang: p?.audioLang, pos: p?.audioPos) { vlc.setAudio(a) }
        if p?.subOff ?? true { vlc.setSubtitle(-1) }
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
        let delay = UInt64(1 << (attempts - 1))
        Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            retryPending = false     // a reopen that fails again counts as the next attempt
            guard reconnecting, !backgrounded else { return }
            Metrics.shared.mark("player.reconnect \(attempts)")
            request.startMs = at
            start(again: true)
        }
    }

    private func start(again: Bool = false) {
        guard let url = catalog.url(request.item) else { vlc.failed = true; return }
        if !again { attempts = 0; reconnecting = false }
        vlc.play(url, startMs: request.startMs, live: isLive)
        if !isLive { user.setResume(request.item, posMs: request.startMs, durMs: 0) }   // in Continue watching from the start
        lastSave = Date()
        showInfo()
        if request.item.kind == .episode && request.next.isEmpty { Task { await loadNextEpisodes() } }
    }

    private func showInfo(long: Bool = false) {
        infoVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: long ? 7_000_000_000 : 4_000_000_000)
            if !Task.isCancelled && picker == nil && scrubMs == nil {
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

    private func finished() {
        if !isLive { user.finished(request.item) }
        if !request.next.isEmpty { playNext() } else { close() }
    }

    private func playNext() {
        guard let n = request.next.first else { return }
        saveResume()
        request.item = n
        request.subtitle = n.sub
        request.startMs = user.resumePoint(n)?.posMs ?? 0
        request.next = Array(request.next.dropFirst())
        controls = false; rootFocus = true
        start()
    }

    /// From Continue watching the episode list is not known yet: read it from the series.
    private func loadNextEpisodes() async {
        guard let sid = request.item.seriesId,
              let d = await catalog.details(MediaItem(kind: .series, id: sid, name: request.item.seriesName ?? "")) else { return }
        let all = d.seasons.flatMap { s in (d.episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == request.item.id }) else { return }
        let title = request.item.seriesName ?? ""
        request.next = all.dropFirst(i + 1).map { s, e in
            MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s) E\(e.num)", img: request.item.img, ext: e.ext, sub: e.title,
                      seriesId: sid, seriesName: title)
        }
    }

    private func close() {
        saveResume()
        vlc.stop()
        dismiss()
    }
}
