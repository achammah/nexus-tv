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
    /// The file's frame rate (0 when VLC does not say).
    var fps: Double {
        for t in player.media?.tracksInformation as? [[String: Any]] ?? [] where (t[VLCMediaTracksInformationType] as? String) == VLCMediaTracksInformationTypeVideo {
            let n = (t[VLCMediaTracksInformationFrameRate] as? NSNumber)?.doubleValue ?? 0, d = (t[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?.doubleValue ?? 0
            if n > 0 && d > 0 { return n / d }
        }
        return 0
    }
    /// Subtitle timing offset in milliseconds (positive: later).
    var subtitleDelayMs: Int {
        get { player.currentVideoSubTitleDelay / 1000 }
        set { player.currentVideoSubTitleDelay = newValue * 1000 }
    }

    /// A subtitle file from outside (OpenSubtitles): added to the playing media and selected. Returns its track index.
    func addSubtitleFile(_ url: URL) async -> Int? {
        let before = Set(subtitleTracks.map(\.0))
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        for _ in 0..<20 {                         // the new track appears in the list a moment later
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let n = subtitleTracks.map(\.0).first(where: { !before.contains($0) }) { setSubtitle(n); return n }
        }
        return nil
    }

    /// The audio format of a track ("AC3", "AAC"…), from the file's track list; nil when VLC does not say.
    func audioFormat(_ id: Int) -> String? {
        let info = player.media?.tracksInformation as? [[String: Any]] ?? []
        for t in info where (t[VLCMediaTracksInformationType] as? String) == VLCMediaTracksInformationTypeAudio {
            guard (t[VLCMediaTracksInformationId] as? NSNumber)?.intValue == id, let c = (t[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value else { continue }
            return Self.formatName(c)
        }
        return nil
    }
    static func formatName(_ fourcc: UInt32) -> String {
        let b = [24, 16, 8, 0].map { UInt8((fourcc >> UInt32($0)) & 0xff) }
        let raw = String(bytes: b.reversed(), encoding: .ascii)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let names = ["a52": "AC3", "eac3": "E-AC3", "mp4a": "AAC", "mpga": "MP3", "mp3": "MP3", "dts": "DTS", "dtsh": "DTS-HD",
                     "mlp": "TrueHD", "trhd": "TrueHD", "opus": "Opus", "flac": "FLAC", "vorb": "Vorbis", "araw": "PCM", "lpcm": "PCM"]
        return names[raw] ?? raw.uppercased()
    }

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
    @ObservedObject private var osub = OpenSubtitles.shared
    // online subtitles for this item: results, state, the one playing (its track index in VLC) and downloaded files
    @State private var online: [OSResult] = []
    @State private var onlineState = ""           // "" not searched, "loading", "done", or an error message
    @State private var onlineFor = ""
    @State private var onlineActive: Int? = nil   // file id
    @State private var onlineTrack: Int? = nil    // its subtitle track index
    @State private var onlineFiles: [Int: URL] = [:]
    @State private var delayTick = 0              // redraws the timing line after Earlier / Later

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
    // next-episode card: 40 s before the end of an episode longer than 80 s, 10 s countdown, once per playback
    @State private var upLeft = 0
    @State private var upDone = false
    @State private var upTask: Task<Void, Never>?
    @FocusState private var upFocus: Bool
    static let upAtMs = 40_000, upCount = 10

    enum TrackKind { case audio, subtitles }
    private var isLive: Bool { request.item.kind == .live }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // the video layer takes the remote while no control has focus (controls are siblings, so clicks reach them)
            ZStack {
                Color.black
                VLCVideoView(controller: vlc)
            }
            .focusable(!controls && picker == nil && upLeft == 0)
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
            if upLeft > 0, let n = request.next.first { upNextCard(n) }
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
        .onChange(of: vlc.timeMs) { _, _ in periodicSave(); upCheck() }
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
        if upLeft > 0 { upHide(); rootFocus = true; return }      // keep watching
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
                if controls && !isLive && !request.next.isEmpty { nextButton.disabled(picker != nil) }
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

    /// Apple TV style: icons only (each still has a spoken name for VoiceOver and tests).
    private var controlBar: some View {
        HStack(spacing: 14) {
            iconButton("gobackward.10", "Back 10 seconds", "back") { vlc.seek(toMs: vlc.timeMs - 10_000) }
            iconButton(vlc.paused ? "play.fill" : "pause.fill", vlc.paused ? "Play" : "Pause", "play") { vlc.toggle() }
            iconButton("goforward.10", "Forward 10 seconds", "fwd") { vlc.seek(toMs: vlc.timeMs + 10_000) }
            iconButton("speaker.wave.2.fill", "Audio", "audio") { openPicker(.audio) }
            iconButton("captions.bubble", "Subtitles", "subs") { openPicker(.subtitles) }
        }
        .focusSection()
    }

    private func iconButton(_ icon: String, _ name: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.ui(26, .semibold)).frame(width: 40) }
            .buttonStyle(PillButtonStyle(height: 64, font: 26, hPad: 18))
            .focused($controlFocus, equals: id)
            .accessibilityLabel(name)
    }

    /// Next episode: an icon on the right, just above the timeline; Up from the control bar reaches it.
    private var nextButton: some View {
        HStack {
            Spacer(minLength: 0)
            iconButton("forward.end.fill", "Next episode", "next") { playNext() }
        }
        .frame(maxWidth: .infinity)
        .focusSection()        // full width: Up from any button of the bar lands here
    }

    private func openPicker(_ k: TrackKind) {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks
        if (list.isEmpty && !(k == .subtitles && osub.ready)) || (k == .audio && list.count < 2) {
            user.show(k == .audio ? "Only one audio track" : "No subtitles in this file"); return
        }
        picker = k
        if k == .subtitles && osub.ready && onlineFor != request.item.key { Task { await loadOnline() } }
    }

    // MARK: online subtitles (OpenSubtitles)

    @ViewBuilder
    private func onlineSection(on: Bool) -> some View {
        let _ = delayTick
        Text("Online · OpenSubtitles").font(.ui(20, .semibold)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 4)
        if onlineState == "loading" || onlineState.isEmpty {
            Text("Searching…").font(.ui(20)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18)
        } else if onlineState != "done" {
            Text(onlineState).font(.ui(20)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18).frame(width: 440, alignment: .leading)
        }
        if on, let fid = onlineActive {
            HStack(spacing: 10) {
                Button { shiftDelay(fid, -500) } label: { Text("Earlier −0.5 s").frame(width: 190) }
                    .focused($trackFocus, equals: 99_998)
                Button { shiftDelay(fid, 500) } label: { Text("Later +0.5 s").frame(width: 190) }
                    .focused($trackFocus, equals: 99_999)
            }
            .buttonStyle(ChipButtonStyle(height: 52, font: 20))
            Text("Timing \(String(format: "%+.1f", Double(vlc.subtitleDelayMs) / 1000)) s").font(.ui(18)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 18)
        }
        ForEach(Array(online.enumerated()), id: \.element.fileId) { i, r in
            let sel = on && onlineActive == r.fileId
            Button {
                picker = nil; controlFocus = "subs"
                Task { await pickOnline(r, remember: true) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark").opacity(sel ? 1 : 0).frame(width: 26)
                    Text(OpenSubtitles.languageName(r.lang) + " · online" + Self.releaseHint(r.release)).lineLimit(1)
                }
                .frame(width: 420, alignment: .leading)
            }
            .buttonStyle(ChipButtonStyle(selected: sel, height: 56, font: 22))
            .accessibilityAddTraits(sel ? .isSelected : [])
            .focused($trackFocus, equals: 100_000 + i)
            .id(100_000 + i)
        }
    }

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
        vlc.subtitleDelayMs += ms
        var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
        all[String(fid)] = vlc.subtitleDelayMs
        UserDefaults.standard.set(all, forKey: "nx.subDelay")
        delayTick += 1
        Metrics.shared.mark("player.osub delay=\(vlc.subtitleDelayMs)")
    }
    /// The release a subtitle was made for, short ("· 1080p AMZN"); nothing when the uploader gave no release.
    static func releaseHint(_ release: String) -> String {
        let r = release.replacingOccurrences(of: ".", with: " ")
        guard let m = r.range(of: "\\b((2160p|1080p|720p|480p)\\s+)?(WEB-?DL|WEBRip|WEB|Blu-?Ray|BDRip|BRRip|HDTV|AMZN|NF|DSNP|HMAX|ATVP)\\b", options: [.regularExpression, .caseInsensitive]) else { return "" }
        return " · " + r[m].trimmingCharacters(in: .whitespaces)
    }

    static func savedDelay(_ fid: Int) -> Int { (UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int])?[String(fid)] ?? 0 }

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
        } catch {
            user.show("Online subtitles failed (\(error.localizedDescription))")
        }
    }

    private func trackPanel(_ k: TrackKind) -> some View {
        let list = k == .audio ? vlc.audioTracks : vlc.subtitleTracks.filter { $0.0 != onlineTrack }
        let current = k == .audio ? vlc.audioIndex : vlc.subtitleIndex
        let onlineOn = k == .subtitles && onlineTrack != nil && current == onlineTrack
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
                                Text(t.0 < 0 ? "Off" : (k == .audio ? audioLabel(t, in: list) : Self.label(t, in: list)))
                            }
                            .frame(width: 420, alignment: .leading)
                        }
                        .buttonStyle(ChipButtonStyle(selected: t.0 == current, height: 56, font: 22))
                        .accessibilityAddTraits(t.0 == current ? .isSelected : [])
                        .focused($trackFocus, equals: t.0)
                        .id(t.0)
                    }
                    if k == .subtitles && osub.ready { onlineSection(on: onlineOn) }
                }
                .padding(4)
            }
            .frame(maxHeight: 520)
            .onAppear {      // opens on the current track, in view
                let f = onlineOn ? (online.firstIndex { $0.fileId == onlineActive }.map { 100_000 + $0 } ?? current) : current
                proxy.scrollTo(f, anchor: .center); trackFocus = f
            }
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
    /// Audio: language and format ("English · AC3"), numbered when two tracks read the same.
    private func audioLabel(_ t: (Int, String), in list: [(Int, String)]) -> String {
        func base(_ x: (Int, String)) -> String { [Self.trackName(x.1).trimmingCharacters(in: .whitespaces), vlc.audioFormat(x.0)].compactMap { $0 }.joined(separator: " · ") }
        let n = base(t), same = list.filter { $0.0 >= 0 && base($0).lowercased() == n.lowercased() }
        guard same.count > 1, let i = same.firstIndex(where: { $0.0 == t.0 }) else { return n }
        return "\(n) \(i + 1)"
    }

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
            user.setTrackPref(request.item) { $0.subOff = t.0 < 0; $0.subLang = lang; $0.subPos = pos; $0.subOnline = nil }
        }
        Metrics.shared.mark("player.choose \(k == .audio ? "audio" : "subs")=\(lang ?? "Off") index=\(t.0)")
        if k == .audio {
            // what VLC really plays a moment later, and whether the clock still moves (audio test)
            let want = t.0, t0 = vlc.timeMs, name = audioLabel(t, in: list)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if vlc.audioIndex != want {          // one retry: VLC can refuse a change while it is still opening the track
                    vlc.setAudio(want)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                Metrics.shared.mark("player.audio-now index=\(vlc.audioIndex) wanted=\(want) clock+\((vlc.timeMs - t0) / 1000)s")
                if vlc.audioIndex != want {
                    let kept = vlc.audioTracks.first { $0.0 == vlc.audioIndex }.map { audioLabel($0, in: list) } ?? "no track"
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
        if !again { attempts = 0; reconnecting = false; upDone = false }
        if onlineFor != request.item.key { online = []; onlineState = ""; onlineActive = nil; onlineTrack = nil; onlineFiles = [:] }
        else { onlineTrack = nil }      // a reopened stream: the remembered choice adds the file again
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
        upHide()
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

    // MARK: next-episode card

    private func upCheck() {
        guard !isLive, upLeft == 0, !upDone, !request.next.isEmpty, scrubMs == nil, picker == nil,
              vlc.lengthMs > Self.upAtMs * 2, vlc.lengthMs - vlc.timeMs <= Self.upAtMs, vlc.timeMs > 0 else { return }
        upDone = true
        upLeft = Self.upCount
        controls = false
        Metrics.shared.mark("player.upnext shown")
        DispatchQueue.main.async { upFocus = true }
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

    private func upHide() { upTask?.cancel(); upTask = nil; upLeft = 0 }

    private func upNextCard(_ n: MediaItem) -> some View {
        let ep = n.name.components(separatedBy: " · ").last ?? n.name
        return VStack(alignment: .leading, spacing: 14) {
            Text("NEXT EPISODE").font(.ui(20, .bold)).tracking(2).foregroundStyle(.white.opacity(0.6))
            Text(n.sub.isEmpty ? ep : ep + " · " + n.sub).font(.ui(30, .semibold)).lineLimit(2).frame(width: 520, alignment: .leading)
            Button { playNext() } label: { Label("Play now · \(upLeft)", systemImage: "play.fill").monospacedDigit() }
                .buttonStyle(PillButtonStyle(height: 60, font: 24))
                .focused($upFocus)
            Text("Menu to keep watching").font(.ui(18)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(30)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.stroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Theme.x0).padding(.bottom, 120)
        .focusSection()
    }

    private func close() {
        saveResume()
        vlc.stop()
        dismiss()
    }
}
