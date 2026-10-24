import Foundation
import Combine
#if os(tvOS)
import TVVLCKit
#else
import VLCKit
#endif

// Shared by the Apple TV app and the Mac app.
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
        // a portal gives a placeholder address: create_link turns it into the real stream just before it opens
        if url.scheme == "nxportal" {
            failed = false; ended = false; started = false; loadPct = 0; timeMs = startMs
            let token = UUID(); resolving = token
            Task { @MainActor in
                let real = await PortalSource.current?.resolve(url)
                guard self.resolving == token else { return }
                guard let real else { self.failed = true; return }
                self.open(real, startMs: startMs, live: live)
            }
            return
        }
        resolving = nil
        open(url, startMs: startMs, live: live)
    }
    private var resolving: UUID?

    private func open(_ url: URL, startMs: Int, live: Bool) {
        self.live = live
        failed = false; ended = false; started = false; loadPct = 0; timeMs = startMs; lengthMs = 0; paused = false
        lastProgress = Date(); lastTime = -1
        let m = VLCMedia(url: url)
        m.addOption(live ? ":network-caching=3000" : ":network-caching=5000")
        m.addOption(":http-reconnect")
        // a playlist can name a user agent and a referrer per channel (EXTVLCOPT, EXTINF attributes, Kodi style url|User-Agent=..)
        let h = StreamHeaderRegistry.shared.headers(for: url.absoluteString)
        m.addOption(":http-user-agent=" + (h?.userAgent.isEmpty == false ? h!.userAgent : "Mozilla/5.0 (AppleTV) NexusTV/1.0"))
        if let r = h?.referrer, !r.isEmpty { m.addOption(":http-referrer=" + r) }
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
        resolving = nil
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


// Track names for menus, shared by both apps.
extension VLCController {
    /// "Track 1 - [English]" -> "English".
    static func trackName(_ s: String) -> String {
        if let r = s.range(of: "\\[([^\\]]+)\\]", options: .regularExpression) { return String(s[r].dropFirst().dropLast()) }
        return s
    }
    /// A subtitle track's name; two tracks with the same language get their number ("English 2").
    static func trackLabel(_ t: (Int, String), in list: [(Int, String)]) -> String {
        let n = trackName(t.1).trimmingCharacters(in: .whitespaces)
        let same = list.filter { $0.0 >= 0 && trackName($0.1).trimmingCharacters(in: .whitespaces).lowercased() == n.lowercased() }
        guard same.count > 1, let i = same.firstIndex(where: { $0.0 == t.0 }) else { return n }
        return "\(n) \(i + 1)"
    }
    /// An audio track: language and format ("English · AC3"), numbered when two read the same.
    func audioLabel(_ t: (Int, String), in list: [(Int, String)]) -> String {
        func base(_ x: (Int, String)) -> String { [Self.trackName(x.1).trimmingCharacters(in: .whitespaces), audioFormat(x.0)].compactMap { $0 }.joined(separator: " · ") }
        let n = base(t), same = list.filter { $0.0 >= 0 && base($0).lowercased() == n.lowercased() }
        guard same.count > 1, let i = same.firstIndex(where: { $0.0 == t.0 }) else { return n }
        return "\(n) \(i + 1)"
    }
}
