import XCTest
@testable import NexusTVMac

/// The live realignment method on synthetic times: the file's own speech times against an online subtitle that is
/// late or early by a known amount, fed as the playback clock runs. No network.
@MainActor
final class SubAutoSyncTests: XCTestCase {
    private var dir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("nx-align", isDirectory: true) }
    /// An SRT whose cue starts are `starts` (ms).
    private func srt(_ starts: [Int], _ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func t(_ ms: Int) -> String { String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000) }
        let body = starts.enumerated().map { "\($0.offset + 1)\n\(t($0.element)) --> \(t($0.element + 1500))\nline \($0.offset)\n" }.joined(separator: "\n")
        let u = dir.appendingPathComponent(name + ".srt")
        try body.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    /// Speech every 2.0 to 4.5 s, irregular (so one offset wins), for ten minutes.
    private let speech: [Int] = { var t = 60_000, out: [Int] = []; var r: UInt64 = 7
        while t < 660_000 { out.append(t); r = r &* 6364136223846793005 &+ 1442695040888963407; t += 2000 + Int(r >> 33) % 2500 }
        return out }()
    private func result(_ id: Int, exact: Bool = false) -> OSResult { var r = OSResult(fileId: id, lang: "en", release: "", downloads: 0, hearingImpaired: false, trusted: false); r.exact = exact; return r }
    /// The tests run inside the app: their made-up subtitle ids leave nothing behind in its settings.
    override func tearDown() {
        var all = UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int] ?? [:]
        for k in all.keys where k.hasPrefix("99000") { all[k] = nil }
        UserDefaults.standard.set(all, forKey: "nx.subDelay")
    }
    private func run(_ sync: SubAutoSync, _ vlc: VLCController, until: Int) { var t = 60_000; while t <= until { vlc.timeMs = t; t += 500 } }

    func testFindsAKnownOffsetWithinAMinuteOfDialogue() async throws {
        SubAutoSync.referenceSource = { _ in self.speech }
        let vlc = VLCController(), sync = SubAutoSync(vlc: vlc)
        // the online file is 3.7 s early: its cue for a line said at t starts at t - 3700
        let file = try srt(speech.map { $0 - 3700 }, "early")
        vlc.timeMs = 60_000
        await sync.start(stream: URL(string: "http://test/a.mkv")!, pick: result(99_000_901), file: file, candidates: [], switchTo: { _ in nil }, log: { _ in })
        run(sync, vlc, until: 120_000)
        XCTAssertEqual(sync.auto, 3700, "offset found from the first minute of dialogue")
        XCTAssertEqual((UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int])?["99000901"], 3700, "kept per subtitle file")
        XCTAssertEqual(sync.shift(-500), 3200, "Earlier / Later works on top")
    }

    func testExactMatchIsLeftAlone() async throws {
        SubAutoSync.referenceSource = { _ in self.speech }
        let vlc = VLCController(), sync = SubAutoSync(vlc: vlc)
        await sync.start(stream: URL(string: "http://test/b.mkv")!, pick: result(99_000_902, exact: true), file: try srt(speech, "exact"), candidates: [], switchTo: { _ in nil }, log: { _ in })
        run(sync, vlc, until: 200_000)
        XCTAssertNil(sync.fileId)
        XCTAssertNil((UserDefaults.standard.dictionary(forKey: "nx.subDelay") as? [String: Int])?["99000902"], "no delay written")
    }

    func testTimedForAnotherCutSwitchesToTheNextCandidate() async throws {
        SubAutoSync.referenceSource = { _ in self.speech }
        let vlc = VLCController(), sync = SubAutoSync(vlc: vlc)
        // a file that matches nothing (cues every 7.3 s, no relation to the speech), then a good one 2.1 s late
        let wrong = try srt(Array(stride(from: 10_000, to: 700_000, by: 7300)), "wrong")
        let good = try srt(speech.map { $0 + 2100 }, "late")
        var switched: Int?
        vlc.timeMs = 60_000
        await sync.start(stream: URL(string: "http://test/c.mkv")!, pick: result(99_000_903), file: wrong, candidates: [result(99_000_904)],
                         switchTo: { next in switched = next.fileId; return good }, log: { _ in })
        run(sync, vlc, until: 200_000)
        for _ in 0..<20 { await Task.yield() }
        run(sync, vlc, until: 260_000)
        XCTAssertEqual(switched, 99_000_904, "switched to the next candidate")
        XCTAssertEqual(sync.fileId, 99_000_904)
        XCTAssertEqual(sync.auto, -2100, "the good file is aligned with the starts already learnt")
    }
}
