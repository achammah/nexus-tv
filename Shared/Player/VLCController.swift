import Foundation
import Combine
import NaturalLanguage
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
    /// The preferred audio language for the next open (a language name such as "English"): passed to VLC as
    /// :audio-language so the file starts in it; the player still checks the track once the list is known.
    var preferredAudio: String?
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
        detectedLang = [:]
        lastOpen = (url, live); released = false; releaseTask?.cancel()
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
        if !live, let name = preferredAudio, let code = Self.languageCode(name) { m.addOption(":audio-language=" + code) }
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
    func toggle() { if player.isPlaying { pause() } else { resume() } }
    func pause() { player.pause(); armRelease() }
    func resume() { if released { reopen() } else { releaseTask?.cancel(); player.play() } }

    // Paused for 2 minutes, or the app hidden: the stream is closed so another device can use the account's only
    // connection; play again reopens it (films where they were, live from now).
    @Published private(set) var released = false
    private var lastOpen: (url: URL, live: Bool)?
    private var releaseTask: Task<Void, Never>?
    private func armRelease() {
        releaseTask?.cancel()
        releaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard let self, !Task.isCancelled, !self.player.isPlaying else { return }
            self.release()
        }
    }
    func release() {
        guard player.media != nil, !released else { return }
        releaseTask?.cancel()
        let at = timeMs
        stop(); released = true; timeMs = at
    }
    func reopen() {
        guard released, let o = lastOpen else { return }
        released = false
        play(o.url, startMs: o.live ? 0 : timeMs, live: o.live)
    }
    func seek(toMs ms: Int) {
        guard player.isSeekable else { return }
        player.time = VLCTime(int: Int32(max(0, ms)))
        timeMs = max(0, ms)
    }

    // Audio and subtitle tracks, as (index, name)
    var audioTracks: [(Int, String)] { zip(player.audioTrackIndexes as? [NSNumber] ?? [], player.audioTrackNames as? [String] ?? []).map { ($0.intValue, $1) }.filter { $0.0 >= 0 } }
    /// Subtitle tracks named by language: a generic name ("Subtitles 1", "Track 2", "und") becomes the language
    /// from the file's own tag, or the language read from the subtitle text (online files).
    var subtitleTracks: [(Int, String)] {
        zip(player.videoSubTitlesIndexes as? [NSNumber] ?? [], player.videoSubTitlesNames as? [String] ?? []).map { ($0.intValue, subtitleName($0.intValue, $1)) }
    }
    /// Languages read from added subtitle files, by track index.
    private var detectedLang: [Int: String] = [:]

    func subtitleName(_ id: Int, _ raw: String) -> String {
        guard id >= 0 else { return raw }
        let inner = Self.trackName(raw).trimmingCharacters(in: .whitespaces)
        if let named = Self.languageName(inner) { return named }        // "eng", "fr", "English"
        guard Self.isGeneric(inner) else { return raw }
        if let d = detectedLang[id] { return d }
        if let tag = trackLanguage(id), let named = Self.languageName(tag) { return named }
        return raw
    }

    /// "Subtitles 1", "Subtitle 2", "Track 3", "Piste 1", "Sub", "Unknown", "und", "": no language in the name.
    static func isGeneric(_ s: String) -> Bool {
        s.isEmpty || s.range(of: "^(sub(title)?s?|sous-titres?|track|piste|text|unknown|undetermined|und|default|stream|spu)?[\\s#._-]*\\d*$",
                             options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// An ISO 639 code or a language name, as an English language name ("fre" and "fr" -> "French"); nil otherwise.
    /// "English" -> "en" (the ISO code VLC's audio-language option takes).
    static func languageCode(_ name: String) -> String? {
        let en = Locale(identifier: "en"), t = name.lowercased()
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            if en.localizedString(forLanguageCode: code)?.lowercased() == t { return code }
        }
        return t.count <= 3 ? t : nil
    }
    private static var nameCache: [String: String?] = [:]
    static func languageName(_ s: String) -> String? {
        if let c = nameCache[s] { return c }
        let r = resolveLanguage(s); nameCache[s] = r; return r
    }
    private static func resolveLanguage(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, t != "und", t != "unknown" else { return nil }
        let en = Locale(identifier: "en")
        let bib = ["fre": "fr", "ger": "de", "dut": "nl", "chi": "zh", "cze": "cs", "gre": "el", "per": "fa", "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "mao": "mi", "may": "ms", "wel": "cy", "tib": "bo"]
        if t.count <= 3, t.allSatisfy(\.isLetter) {
            let code = bib[t] ?? t
            if let n = en.localizedString(forLanguageCode: code), n.lowercased() != code { return n.capitalized(with: en) }
            return nil
        }
        // already a language name ("English", "français"): normalise it to English
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            if let n = en.localizedString(forLanguageCode: code), n.lowercased() == t { return n }
            if let own = Locale(identifier: code).localizedString(forLanguageCode: code), own.lowercased() == t, let n = en.localizedString(forLanguageCode: code) { return n }
        }
        return nil
    }

    /// The language tag of a text track in the file, when VLC reads one.
    private func trackLanguage(_ id: Int) -> String? {
        for t in player.media?.tracksInformation as? [[String: Any]] ?? [] where (t[VLCMediaTracksInformationType] as? String) == VLCMediaTracksInformationTypeText {
            guard (t[VLCMediaTracksInformationId] as? NSNumber)?.intValue == id else { continue }
            if let l = t[VLCMediaTracksInformationLanguage] as? String, !l.isEmpty { return l }
            if let d = t[VLCMediaTracksInformationDescription] as? String, Self.languageName(d) != nil { return d }
        }
        return nil
    }

    /// The language of a subtitle file's text (SRT / VTT / ASS), from its dialogue lines.
    static func detectLanguage(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: d.prefix(200_000), as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).filter { l in
            !l.contains("-->") && !l.allSatisfy { $0.isNumber || $0.isWhitespace } && !l.hasPrefix("WEBVTT") && !l.hasPrefix("[")
        }.map { $0.replacingOccurrences(of: "<[^>]+>|\\{[^}]*\\}", with: "", options: .regularExpression) }
        let sample = lines.prefix(400).joined(separator: " ")
        guard sample.count > 40 else { return nil }
        let r = NLLanguageRecognizer(); r.processString(sample)
        guard let lang = r.dominantLanguage, (r.languageHypotheses(withMaximum: 1)[lang] ?? 0) > 0.5 else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue)
    }
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
        let lang = url.isFileURL ? await Task.detached { Self.detectLanguage(url) }.value : nil
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        for _ in 0..<20 {                         // the new track appears in the list a moment later
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let n = subtitleTracks.map(\.0).first(where: { !before.contains($0) }) { if let lang { detectedLang[n] = lang }; setSubtitle(n); return n }
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

// MARK: - Track labels (player redesign 2026-10-25; both apps use them)

/// What the player knows about one audio or subtitle track.
struct TrackFacts: Equatable {
    var index: Int
    /// VLC's own name, e.g. "Commentary - [English]"; the title keywords are read from it.
    var raw: String
    /// Language as an English name ("English", "German"); nil when the file carries no tag and detection found none.
    var language: String?
    /// "5.1", "stereo" ... (audio only) and the codec ("AC3").
    var channels: String? = nil
    var codec: String? = nil
}

/// How a track reads in the popup: `name` on the left, `detail` in grey on the right, a round flag before the name.
struct TrackLabel: Equatable {
    var name: String            // "English", "English · Descriptive", "Track 6"
    var detail: String          // "5.1 · AC3", "hearing impaired", "unknown language · stereo"
    var flag: String?           // asset name in Shared/Brand.xcassets ("flag-gb"); nil = a grey circle
    var short: String           // the second word of the bar button: "English", "Track 6"
}

enum TrackLabels {
    /// Title keywords that tell two tracks of one language apart, in the order they are tried.
    static let keywords: [(label: String, pattern: String)] = [
        ("Descriptive", "descriptive|audio[ -]?description|\\bAD\\b|visually impaired"),
        ("Commentary", "commentary"),
        ("SDH", "\\bSDH\\b|hearing[ -]impaired|closed[ -]caption|\\bCC\\b"),
        ("Forced", "forced|\\bsigns?\\b"),
        ("Original", "original|\\bVO\\b|\\bOV\\b"),
    ]

    static func keyword(in raw: String) -> String? {
        for k in keywords where raw.range(of: k.pattern, options: [.regularExpression, .caseInsensitive]) != nil { return k.label }
        return nil
    }

    /// "5.1" for 6 channels, "stereo" for 2 ... ; nil for 0.
    static func channelName(_ n: Int) -> String? {
        switch n {
        case 0: return nil
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(n) ch"
        }
    }

    /// Round flag for a language (the language's main country); nil when unsure: the popup then draws a grey circle.
    static func flag(forLanguage name: String?) -> String? {
        guard let name, let code = VLCController.languageCode(name)?.lowercased() else { return nil }
        let country = ["en": "gb", "fr": "fr", "de": "de", "nl": "nl", "es": "es", "it": "it", "pt": "pt", "ja": "jp", "ko": "kr",
                       "zh": "cn", "ru": "ru", "ar": "sa", "tr": "tr", "pl": "pl", "sv": "se", "da": "dk", "no": "no", "nb": "no",
                       "fi": "fi", "el": "gr", "he": "il", "hi": "in", "cs": "cz", "hu": "hu", "ro": "ro", "uk": "ua", "th": "th",
                       "vi": "vn", "id": "id", "ms": "my", "fa": "ir", "bg": "bg", "hr": "hr", "sr": "rs", "sk": "sk", "sl": "si",
                       "ca": "es", "et": "ee", "lv": "lv", "lt": "lt", "is": "is", "ga": "ie", "sq": "al", "mk": "mk", "bn": "bd",
                       "ur": "pk", "ta": "in", "te": "in"][code]
        return country.map { "flag-" + $0 }
    }

    /// The labels of one list (audio or subtitles). The rule:
    /// 1. the language from the tag; no tag: "Track N" (N = its place in the list) with detail "unknown language";
    /// 2. a title keyword (Descriptive, Commentary, SDH, Forced, Original) joins the name, as on the approved boards
    ///    ("Japanese · Original"); it is what tells two tracks of one language apart;
    /// 3. channels and codec ride in the detail (audio), so two tracks that still read alike differ there;
    /// 4. only a pair identical on every point gets "Track N" last. Never "English 1 / English 2".
    static func labels(_ tracks: [TrackFacts], audio: Bool) -> [Int: TrackLabel] {
        let real = tracks.filter { $0.index >= 0 }
        var out: [Int: TrackLabel] = [:]
        var pending: [(TrackFacts, Int, String, String)] = []     // track, position, name, detail
        for (i, t) in real.enumerated() {
            let kw = keyword(in: t.raw)
            let tech = audio ? [t.channels, t.codec].compactMap { $0 }.joined(separator: " · ")
                             : (kw == "SDH" ? "hearing impaired" : (kw == "Forced" ? "signs only" : ""))
            if let lang = t.language {
                let name = kw.map { lang + " · " + $0 } ?? lang
                pending.append((t, i + 1, name, tech))
            } else {
                let detail = (["unknown language"] + (tech.isEmpty ? [] : [tech])).joined(separator: " · ")
                out[t.index] = TrackLabel(name: "Track \(i + 1)", detail: detail, flag: nil, short: "Track \(i + 1)")
            }
        }
        for (t, pos, name, detail) in pending {
            let twins = pending.filter { $0.2.lowercased() == name.lowercased() && $0.3 == detail }.count
            let final = twins > 1 ? name + " · Track \(pos)" : name
            out[t.index] = TrackLabel(name: final, detail: detail, flag: flag(forLanguage: t.language), short: t.language ?? final)
        }
        return out
    }
}

extension VLCController {
    /// Channels ("5.1") of an audio track, from the file's track list; nil when VLC does not say.
    func audioChannels(_ id: Int) -> String? {
        for t in player.media?.tracksInformation as? [[String: Any]] ?? [] where (t[VLCMediaTracksInformationType] as? String) == VLCMediaTracksInformationTypeAudio {
            guard (t[VLCMediaTracksInformationId] as? NSNumber)?.intValue == id else { continue }
            return TrackLabels.channelName((t[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue ?? 0)
        }
        return nil
    }
    /// The audio tracks as the label rule needs them.
    var audioFacts: [TrackFacts] {
        audioTracks.map { TrackFacts(index: $0.0, raw: $0.1, language: Self.languageName(Self.trackName($0.1).trimmingCharacters(in: .whitespaces)),
                                     channels: audioChannels($0.0), codec: audioFormat($0.0)) }
    }
    /// The subtitle tracks as the label rule needs them (the language already read from the tag or from the text).
    var subtitleFacts: [TrackFacts] {
        let raws = zip(player.videoSubTitlesIndexes as? [NSNumber] ?? [], player.videoSubTitlesNames as? [String] ?? []).map { ($0.intValue, $1) }
        return subtitleTracks.map { t in
            let raw = raws.first { $0.0 == t.0 }?.1 ?? t.1
            return TrackFacts(index: t.0, raw: raw, language: Self.languageName(Self.trackName(t.1).trimmingCharacters(in: .whitespaces)))
        }
    }
}
