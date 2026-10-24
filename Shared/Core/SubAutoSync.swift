import Foundation
import Combine

/// Live realignment of an online subtitle that was not made for this exact file (the Frame's auto sync, ported).
/// The reference is the file's own text subtitle track: every one of its cue starts is a real speech time. VLCKit
/// gives no callback for the cues of an embedded track, so the start times are read from the file's Matroska index
/// (its Cues element lists every subtitle block with its time; one range read near the end of the file) and fed to the
/// method as the playback clock passes them, as if the track were being shown. Not for MP4 files (no index of this kind).
@MainActor
final class SubAutoSync {
    // the method's numbers (Frame player.js startAlign / refCue / align / useOnline)
    static let window = 20_000          // online cues considered around a reference start (ms)
    static let bin = 100                // vote bin (ms)
    static let alignEvery = 4           // align after every 4th reference start
    static let minStarts = 6            // ... once there are at least this many
    static let decideStarts = 10        // an offset is applied only with this many starts
    static let agreement = 0.4          // ... and this share of them agreeing (±200 ms)
    static let keepStarts = 40          // sliding window: the last 40 starts (follows a slow drift)
    static let giveUpStarts = 16        // no agreement after this many: the file is timed for another cut
    static let fpsTolerance = 0.06      // rescale the clock when the frame rates differ by less than this

    private let vlc: VLCController
    private var sink: AnyCancellable?
    /// Reference speech times (ms, video clock), every one in the file, sorted; and the next one to feed.
    private var reference: [Int] = []
    private var nextRef = 0
    private var lastClock = 0
    /// The method's state, kept across a switch to another candidate.
    private var starts: [Int] = []
    private var fed = 0
    /// The online file being aligned: its cue starts (ms, subtitle clock), its id, the clock scale, the candidates left.
    private var cues: [Int] = []
    private(set) var fileId: Int?
    private var k = 1.0
    private var alternatives: [OSResult] = []
    private var switching = false
    /// Offset found by the method, and the owner's own Earlier / Later on top.
    private(set) var auto = 0
    private var manual = 0
    private var log: (String) -> Void = { _ in }
    /// Swaps to another candidate: downloads and shows it, returns its local file (nil: not shown).
    private var switchTo: ((OSResult) async -> URL?)?
    private static var referenceCache: [URL: [Int]] = [:]
    /// Where the reference starts come from (tests pass their own).
    static var referenceSource: (URL) async -> [Int]? = { await MatroskaSubIndex.referenceStarts($0) }
    private var referenceFor: URL?

    init(vlc: VLCController) { self.vlc = vlc }

    /// Starts on a picked online subtitle. An exact-file match needs nothing; otherwise the reference is read once
    /// per stream and the online cues are matched as playback runs.
    func start(stream: URL, pick: OSResult, file: URL, candidates: [OSResult],
               switchTo: @escaping (OSResult) async -> URL?, log: @escaping (String) -> Void) async {
        self.log = log; self.switchTo = switchTo
        guard !pick.exact else { stop(); log("player.align skip exact"); return }
        let keepState = fileId != nil && switching
        if !keepState { starts = []; fed = 0 }
        use(pick, file: file, candidates: candidates)
        if reference.isEmpty || stream != referenceFor {
            referenceFor = stream
            let ref: [Int]
            if let c = Self.referenceCache[stream] { ref = c } else { ref = await Self.referenceSource(stream) ?? []; Self.referenceCache[stream] = ref }
            reference = ref
            log("player.align reference starts=\(ref.count)")
            guard !ref.isEmpty else { return }
        }
        nextRef = reference.firstIndex { $0 >= vlc.timeMs } ?? reference.count
        lastClock = vlc.timeMs
        if sink == nil { sink = vlc.$timeMs.sink { [weak self] t in self?.clock(t) } }
    }

    func stop() {
        sink = nil; fileId = nil; cues = []; starts = []; fed = 0; auto = 0; manual = 0; alternatives = []; switching = false
        reference = []; nextRef = 0
    }

    /// The timing kept for a subtitle file (found or set by hand). Test hook: -NXSubDelayStart ms gives a file with no
    /// kept timing that start (a subtitle that begins several seconds off).
    static func savedDelay(_ fid: Int) -> Int {
        if let d = (UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int])?[String(fid)] { return d }
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "NXSubDelayStart")
        #else
        return 0
        #endif
    }

    /// Earlier / Later on top of the found offset; returns the delay to show and keep.
    func shift(_ ms: Int) -> Int { manual += ms; return apply() }

    private func use(_ r: OSResult, file: URL, candidates: [OSResult]) {
        fileId = r.fileId
        cues = SRT.starts(file)
        let vf = vlc.fps
        k = (vf > 0 && r.fps > 0 && abs(vf - r.fps) > 0.05 && abs(vf / r.fps - 1) < Self.fpsTolerance) ? vf / r.fps : 1
        let saved = Self.savedDelay(r.fileId)
        auto = saved; manual = 0
        alternatives = candidates
        switching = false
        log("player.align file=\(r.fileId) cues=\(cues.count) k=\(String(format: "%.4f", k)) saved=\(saved)")
    }

    /// The playback clock: every reference start it passes is a cue the track would show now.
    private func clock(_ t: Int) {
        guard fileId != nil, !reference.isEmpty else { return }
        if t < lastClock || t - lastClock > 5_000 {          // a seek: start from the new position, keep what was learnt
            nextRef = reference.firstIndex { $0 >= t } ?? reference.count
            lastClock = t; return
        }
        lastClock = t
        while nextRef < reference.count, reference[nextRef] <= t {
            refCue(reference[nextRef]); nextRef += 1
        }
    }

    private func refCue(_ t: Int) {
        starts.append(t); if starts.count > Self.keepStarts { starts.removeFirst() }
        fed += 1
        if fed % Self.alignEvery == 0 && starts.count >= Self.minStarts { align() }
    }

    private func align() {
        guard !cues.isEmpty else { return }
        var bins: [Int: Int] = [:]
        for s in starts {
            let te = Int((Double(s) * k).rounded())
            var lo = 0, hi = cues.count - 1
            while lo < hi { let m = (lo + hi) >> 1; if cues[m] < te - Self.window { lo = m + 1 } else { hi = m } }
            var j = lo
            while j < cues.count && cues[j] <= te + Self.window {
                let b = Int((Double(te - cues[j]) / Double(Self.bin)).rounded()); bins[b, default: 0] += 1; j += 1
            }
        }
        var best = 0, score = 0
        for key in bins.keys {
            let c = (-2...2).reduce(0) { $0 + (bins[key + $1] ?? 0) }
            if c > score { score = c; best = key * Self.bin }
        }
        let ok = starts.count >= Self.decideStarts && Double(score) >= Double(starts.count) * Self.agreement
        if ok { auto = best; _ = apply() }
        log("player.align off=\(best) score=\(score) n=\(starts.count) used=\(ok) file=\(fileId ?? 0)")
        // after a minute of dialogue with no agreement, this file is timed for another cut: try the next one
        if !ok, starts.count >= Self.giveUpStarts, !alternatives.isEmpty, !switching, let go = switchTo {
            let next = alternatives.removeFirst(), rest = alternatives
            switching = true
            log("player.align switch to=\(next.fileId)")
            Task { @MainActor in
                guard let file = await go(next) else { self.switching = false; return }
                self.switching = true
                self.use(next, file: file, candidates: rest)
            }
        }
    }

    /// Shows the found offset plus the owner's own shift, and keeps it for this subtitle file.
    private func apply() -> Int {
        let d = auto + manual
        vlc.subtitleDelayMs = d
        if let fid = fileId {
            var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
            all[String(fid)] = d
            UserDefaults.standard.set(all, forKey: "nx.subDelay")
        }
        return d
    }
}

/// Cue start times of an SRT file (ms), sorted.
enum SRT {
    static func starts(_ file: URL) -> [Int] {
        guard let d = try? Data(contentsOf: file) else { return [] }
        let text = String(decoding: d, as: UTF8.self)
        let re = try! NSRegularExpression(pattern: "(\\d+):(\\d+):(\\d+)[,.](\\d+)\\s*-->")
        var out: [Int] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func g(_ i: Int) -> Int { Int(text[Range(m.range(at: i), in: text)!]) ?? 0 }
            out.append(((g(1) * 60 + g(2)) * 60 + g(3)) * 1000 + g(4))
        }
        return out.sorted()
    }
}

/// Reads the start times of a Matroska file's text subtitle track from its index (Cues), with HTTP range reads:
/// the head (tracks and the seek table), then the Cues element. English first, else the first text track; a track
/// with fewer than 100 entries (forced lines only) is passed over when a fuller one exists.
enum MatroskaSubIndex {
    static func referenceStarts(_ url: URL) async -> [Int]? {
        guard let head = await range(url, 0, 256 * 1024) else { return nil }
        guard let (segStart, _) = child(head, 0, head.count, 0x18538067) else { return nil }
        var seeks: [Int: Int] = [:], tracks: [(n: Int, lang: String, text: Bool)] = []
        var scale = 1_000_000
        for (id, p, size) in children(head, segStart, head.count) {
            guard let size else { break }
            switch id {
            case 0x114D9B74:
                for (sid, sp, ss) in children(head, p, p + size) where sid == 0x4DBB {
                    var eid = 0, pos = 0
                    for (e, ep, es) in children(head, sp, sp + (ss ?? 0)) {
                        if e == 0x53AB { eid = uint(head, ep, es ?? 0) }
                        if e == 0x53AC { pos = uint(head, ep, es ?? 0) }
                    }
                    seeks[eid] = pos
                }
            case 0x1549A966:
                for (e, ep, es) in children(head, p, p + size) where e == 0x2AD7B1 { scale = uint(head, ep, es ?? 0) }
            case 0x1654AE6B:
                for (e, ep, es) in children(head, p, p + size) where e == 0xAE {
                    var n = 0, type = 0, lang = "eng", codec = ""
                    for (f, fp, fs) in children(head, ep, ep + (es ?? 0)) {
                        let s = fs ?? 0
                        if f == 0xD7 { n = uint(head, fp, s) }
                        if f == 0x83 { type = uint(head, fp, s) }
                        if f == 0x22B59C { lang = String(decoding: head[fp..<min(head.count, fp + s)], as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
                        if f == 0x86 { codec = String(decoding: head[fp..<min(head.count, fp + s)], as: UTF8.self) }
                    }
                    if type == 0x11 { tracks.append((n, lang, codec.hasPrefix("S_TEXT") || codec.hasPrefix("S_ASS") || codec.hasPrefix("S_SSA"))) }
                }
            default: break
            }
            if id == 0x1F43B675 { break }      // the first cluster: the head is over
        }
        let text = tracks.filter(\.text)
        guard !text.isEmpty, let cuesAt = seeks[0x1C53BB6B] else { return nil }
        guard let top = await range(url, segStart + cuesAt, 16) else { return nil }
        let (eid, l1) = vint(top, 0, keepMarker: true), (size, l2) = vint(top, l1, keepMarker: false)
        guard eid == 0x1C53BB6B, size > 0, size < 64 << 20, let body = await range(url, segStart + cuesAt + l1 + l2, size) else { return nil }
        var byTrack: [Int: [Int]] = [:]
        let wanted = Set(text.map(\.n))
        for (id, p, s) in children(body, 0, body.count) where id == 0xBB {
            var t = 0, trs: [Int] = []
            for (e, ep, es) in children(body, p, p + (s ?? 0)) {
                if e == 0xB3 { t = uint(body, ep, es ?? 0) }
                if e == 0xB7 { for (f, fp, fs) in children(body, ep, ep + (es ?? 0)) where f == 0xF7 { trs.append(uint(body, fp, fs ?? 0)) } }
            }
            for tr in trs where wanted.contains(tr) { byTrack[tr, default: []].append(Int(Double(t) * Double(scale) / 1_000_000)) }
        }
        let full = text.filter { (byTrack[$0.n]?.count ?? 0) >= 100 }
        let pool = full.isEmpty ? text : full
        let pick = pool.first { $0.lang.hasPrefix("en") } ?? pool.first!
        let starts = Array(Set(byTrack[pick.n] ?? [])).sorted()
        return starts.isEmpty ? nil : starts
    }

    private static func range(_ url: URL, _ from: Int, _ count: Int) async -> [UInt8]? {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("bytes=\(from)-\(from + count - 1)", forHTTPHeaderField: "Range")
        r.setValue("VLC/3.0", forHTTPHeaderField: "User-Agent")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse, h.statusCode == 206 else { return nil }
        return [UInt8](d)
    }
    static func vint(_ b: [UInt8], _ i: Int, keepMarker: Bool) -> (Int, Int) {
        guard i < b.count else { return (0, 1) }
        let x = b[i]; var n = 1
        while n <= 8 && x & (0x80 >> (n - 1)) == 0 { n += 1 }
        var v = keepMarker ? Int(x) : Int(x & (0xFF >> n))
        for j in 1..<n where i + j < b.count { v = (v << 8) | Int(b[i + j]) }
        return (v, n)
    }
    static func uint(_ b: [UInt8], _ i: Int, _ n: Int) -> Int { (0..<n).reduce(0) { i + $1 < b.count ? ($0 << 8) | Int(b[i + $1]) : $0 } }
    /// Elements between `from` and `to`: id, data start, size (nil = unknown size, the rest of the parent).
    static func children(_ b: [UInt8], _ from: Int, _ to: Int) -> [(Int, Int, Int?)] {
        var out: [(Int, Int, Int?)] = [], i = from
        while i < min(to, b.count) {
            let (id, l1) = vint(b, i, keepMarker: true), (size, l2) = vint(b, i + l1, keepMarker: false)
            let unknown = size == (1 << (7 * l2)) - 1
            out.append((id, i + l1 + l2, unknown ? nil : size))
            if unknown { break }
            i += l1 + l2 + size
        }
        return out
    }
    private static func child(_ b: [UInt8], _ from: Int, _ to: Int, _ want: Int) -> (Int, Int?)? {
        children(b, from, to).first { $0.0 == want }.map { ($0.1, $0.2) }
    }
}
