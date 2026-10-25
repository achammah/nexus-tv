import Foundation

// The player rules that need no screen: track labels, the credits cue, the "still watching?" counters.
// Private copies for the Mac lane.
// TODO(merge): use Shared.creditsCue / Shared.MacTrackLabel / Shared.AutoplayState once the tvOS lane has added them to Shared.

// MARK: - Track labels (rule 2)

/// One audio or subtitle track as the player reports it.
struct TrackInput: Equatable {
    var id: Int
    /// VLC's own name, for example "Track 1 - [English]".
    var raw: String
    /// The language as an English name when the caller already knows it (subtitle detection); else read from `raw`.
    var language: String? = nil
    /// The file's title for the track ("Commentary", "SDH").
    var title: String? = nil
    var channels: Int? = nil
    var codec: String? = nil
}

/// What the audio and subtitle popups show for one track: a language name, then what tells two tracks of the
/// same language apart, and never "English 1 / English 2".
struct MacTrackLabel: Equatable, Identifiable {
    var id: Int
    /// "English", "English · Descriptive", "Track 6".
    var text: String
    /// The grey text at the right of the row: "5.1 · AC3", "stereo", "unknown language · stereo".
    var detail: String
    var language: String?
    /// The round flag asset ("flag-gb"); nil draws a grey circle.
    var flag: String?
    /// The whole label on one line: "English · Descriptive", "Track 6 · unknown language".
    var full: String { language == nil ? text + " · unknown language" : text }

    /// Language from the track's tag (or the detected one), then a discriminator only when two tracks share a language:
    /// Descriptive, Commentary, Original, SDH or Forced from the track title, else the channels and the codec.
    /// No language at all: "Track N" with "unknown language" at the right (N counts from 1 in this list).
    static func make(tracks: [TrackInput]) -> [MacTrackLabel] {
        struct Row { var t: TrackInput; var lang: String?; var key: String?; var detail: String }
        var rows: [Row] = tracks.map { t in
            var lang = t.language
            if lang == nil {
                let inner = VLCController.trackName(t.raw).trimmingCharacters(in: .whitespaces)
                if !VLCController.isGeneric(inner) { lang = VLCController.languageName(inner) ?? (inner.isEmpty ? nil : inner) }
            }
            let key = keyword(in: [t.title, t.raw])
            var parts: [String] = []
            if let c = t.channels { parts.append(channelName(c)) }
            if let c = t.codec, !c.isEmpty { parts.append(c) }
            return Row(t: t, lang: lang, key: key, detail: parts.joined(separator: " · "))
        }
        // subtitle rows with no channels still say what a keyword means
        for i in rows.indices where rows[i].detail.isEmpty && rows[i].t.channels == nil && rows[i].t.codec == nil {
            if rows[i].key == "SDH" { rows[i].detail = "hearing impaired" } else if rows[i].key == "Forced" { rows[i].detail = "signs only" }
        }
        var out: [MacTrackLabel] = []
        for (n, r) in rows.enumerated() {
            guard let lang = r.lang else {
                out.append(MacTrackLabel(id: r.t.id, text: "Track \(n + 1)", detail: (["unknown language"] + (r.detail.isEmpty ? [] : [r.detail])).joined(separator: " · "),
                                      language: nil, flag: nil))
                continue
            }
            let shared = rows.filter { $0.lang?.lowercased() == lang.lowercased() }.count > 1
            let text = shared && r.key != nil ? lang + " · " + r.key! : lang
            out.append(MacTrackLabel(id: r.t.id, text: text, detail: r.detail, language: lang, flag: LanguageFlag.asset(lang)))
        }
        // two rows still reading the same (same language, no keyword, same channels and codec): the position tells them apart
        let before = out
        for i in out.indices where before.filter({ $0.text == before[i].text && $0.detail == before[i].detail }).count > 1 {
            out[i].text += " · Track \(i + 1)"
        }
        return out
    }

    static func keyword(in texts: [String?]) -> String? {
        let t = texts.compactMap { $0 }.joined(separator: " ")
        let table: [(String, String)] = [
            ("Descriptive", "descriptive|audio[ _-]?description|visually impaired|\\bAD\\b"),
            ("Commentary", "commentary|director"),
            ("SDH", "\\bSDH\\b|hearing[ _-]?impaired|\\bHI\\b"),
            ("Forced", "forced|\\bsigns?\\b"),
            ("Original", "original|\\bVO\\b|\\bOV\\b"),
        ]
        for (name, pattern) in table where t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return name }
        return nil
    }

    static func channelName(_ n: Int) -> String {
        switch n { case 1: "mono"; case 2: "stereo"; case 6: "5.1"; case 8: "7.1"; default: "\(n) ch" }
    }
}

/// The round flag drawn before a language name (Shared/Brand.xcassets "flag-<iso>").
enum LanguageFlag {
    private static let country: [String: String] = [
        "en": "gb", "fr": "fr", "de": "de", "nl": "nl", "es": "es", "it": "it", "pt": "pt", "ru": "ru", "ja": "jp", "zh": "cn", "ko": "kr",
        "ar": "sa", "tr": "tr", "pl": "pl", "sv": "se", "da": "dk", "no": "no", "nb": "no", "fi": "fi", "el": "gr", "he": "il", "hi": "in",
        "cs": "cz", "sk": "sk", "hu": "hu", "ro": "ro", "bg": "bg", "uk": "ua", "sr": "rs", "hr": "hr", "sl": "si", "th": "th", "vi": "vn",
        "id": "id", "ms": "my", "fa": "ir", "is": "is", "et": "ee", "lv": "lv", "lt": "lt", "sq": "al", "mk": "mk", "ka": "ge", "hy": "am",
        "az": "az", "kk": "kz", "bn": "bd", "ur": "pk", "ta": "in", "te": "in", "ga": "ie", "cy": "gb", "af": "za", "sw": "ke", "tl": "ph",
    ]
    /// The flag asset for a language name or code ("English", "fre", "fr"); nil when there is none.
    static func asset(_ language: String) -> String? {
        guard let code = VLCController.languageCode(language), let c = country[code.lowercased()] else { return nil }
        return "flag-" + c
    }
}

// MARK: - Credits cue (rule 5)

/// Where the credits start, per show: seconds BEFORE the end, the last 5 samples, kept next to the track preferences.
struct CreditsMemory {
    var defaults: UserDefaults = .standard
    var key = "nx.credits"
    static let shared = CreditsMemory()
    static let keep = 5
    /// A sample counts only when the credits start within this many seconds of the end.
    static let window = 480.0

    func samples(_ seriesId: String) -> [Double] { (defaults.dictionary(forKey: key) as? [String: [Double]])?[seriesId] ?? [] }
    /// The median of the last 5 samples (nil: this show has none yet).
    func median(_ seriesId: String) -> Double? {
        let s = samples(seriesId).sorted()
        guard !s.isEmpty else { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    /// Keeps one sample (seconds before the end); ignored outside 5 s … 8 min.
    func record(_ seriesId: String, secondsBeforeEnd: Double) {
        guard secondsBeforeEnd >= 5, secondsBeforeEnd <= Self.window else { return }
        var all = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        var s = all[seriesId] ?? []
        s.append(secondsBeforeEnd)
        all[seriesId] = Array(s.suffix(Self.keep))
        defaults.set(all, forKey: key)
    }
}

enum Credits {
    /// Rule 5b: the subtitles go quiet this long inside the last `lastSecs`.
    static let quietSecs = 45.0, lastSecs = 360.0
    /// Rule 5c: the last 2 % of the runtime, never under 20 s.
    static let tailShare = 0.02, tailMin = 20.0

    /// Rule 5b on a list of subtitle cue starts (seconds): the credits start where the last quiet stretch of 45 s or more
    /// inside the last 6 minutes begins (3 s after the last cue before it). nil without cues or without such a stretch.
    static func quietPoint(cueStarts: [Double], duration: Double) -> Double? {
        let s = cueStarts.sorted()
        guard !s.isEmpty, duration > lastSecs else { return nil }
        let from = duration - lastSecs
        var best: Double?
        for (i, start) in s.enumerated() where start < duration {
            let next = i + 1 < s.count ? s[i + 1] : duration
            guard next - start >= quietSecs, next > from else { continue }
            best = max(start + 3, from)
        }
        return best
    }
}

/// When the credits start in this episode, in seconds from its start, in order of trust:
/// (a) the show's remembered credits start (median of its last 5 samples, seconds before the end);
/// (b) no memory: the embedded subtitle cues go quiet for 45 s inside the last 6 minutes (`cueStarts`, seconds);
/// (c) no subtitles: the last 2 % of the runtime, never under 20 s.
/// The cue never comes before half of the episode.
func creditsCue(for seriesId: String?, duration: Double, memory: CreditsMemory = .shared, cueStarts: [Double] = []) -> Double {
    guard duration > 0 else { return 0 }
    let floor = duration / 2
    if let sid = seriesId, let m = memory.median(sid) { return max(floor, duration - m) }
    if let q = Credits.quietPoint(cueStarts: cueStarts, duration: duration) { return max(floor, q) }
    return max(floor, duration - max(Credits.tailMin, duration * Credits.tailShare))
}

// MARK: - Autoplay counters (rules 4 and 6)

/// What the session remembers to decide the end-card ring and the "Still watching?" toast.
struct AutoplayState {
    static let after = 2, afterQuiet = 4
    static let keyFreeSecs: TimeInterval = 90 * 60
    static let quickAnswerSecs = 10.0

    /// Autoplayed episodes since the last key press.
    private(set) var run = 0
    private(set) var lastKeyAt: Date?
    private(set) var lastMouseAt: Date?
    /// Rule 4: the previous episode of this session reached its card and was not seeked.
    private(set) var previousCardWithoutSeek = false
    private var cardThisEpisode = false
    private var seekedThisEpisode = false
    private var threshold = AutoplayState.after
    private var quickKeeps = 0

    mutating func key(at now: Date = Date()) { lastKeyAt = now; run = 0 }
    mutating func mouse(at now: Date = Date()) { lastMouseAt = now }
    /// A seek by the user (arrow, timeline).
    mutating func seeked() { seekedThisEpisode = true }

    /// The end card appears. Returns whether its ring runs (rule 4: the previous episode also reached its card without a seek).
    mutating func cardReached() -> Bool { cardThisEpisode = true; return previousCardWithoutSeek }

    /// A new episode starts; `autoplayed` = it followed the previous one by itself. Returns whether to ask "Still watching?".
    mutating func episodeStarted(autoplayed: Bool, windowKey: Bool, at now: Date = Date()) -> Bool {
        previousCardWithoutSeek = cardThisEpisode && !seekedThisEpisode
        cardThisEpisode = false; seekedThisEpisode = false
        guard autoplayed else { run = 0; return false }
        run += 1
        guard run >= threshold else { return false }
        if let k = lastKeyAt, now.timeIntervalSince(k) < Self.keyFreeSecs { return false }
        if windowKey, let m = lastMouseAt, now.timeIntervalSince(m) < Self.keyFreeSecs { return false }
        run = 0; threshold = Self.after
        return true
    }

    /// The answer to the toast. Two "Keep watching" within 10 s each: the next ask waits 4 autoplayed episodes.
    mutating func answered(keep: Bool, afterSecs: Double) {
        run = 0
        guard keep else { return }
        quickKeeps = afterSecs <= Self.quickAnswerSecs ? quickKeeps + 1 : 0
        if quickKeeps >= 2 { threshold = Self.afterQuiet; quickKeeps = 0 }
    }
}

// MARK: - Small helpers

enum PlayerFormat {
    /// "10:34" or "1:02:03".
    static func clock(_ secs: Int) -> String {
        let s = max(0, secs)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
    /// "57 min".
    static func minutes(_ secs: Int) -> String { "\(max(1, Int((Double(secs) / 60).rounded()))) min" }
    /// The season and episode numbers of an episode item name ("Show · S1 E3").
    static func seasonEpisode(_ name: String) -> (season: String, episode: Int)? {
        guard let m = name.range(of: "S(\\d+) E(\\d+)$", options: .regularExpression) else { return nil }
        let n = name[m].split(separator: " ").map { $0.filter(\.isNumber) }
        guard n.count == 2, let e = Int(n[1]) else { return nil }
        return (String(Int(n[0]) ?? 0), e)
    }
}
