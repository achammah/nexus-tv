import SwiftUI

/// The state of the first-launch screen and of "Add a source": which type, what was typed, what the check said.
/// Both apps draw it with OnboardingScreen.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Phase { case idle, checking, done }
    enum Note { case none, wait, bad, ok }

    @Published var type: SourceType = .xtream { didSet { if type != oldValue { clearResult() } } }
    @Published var values: [SourceType: [String]] = [.xtream: ["", "", ""], .m3u: ["", "", ""], .portal: ["", "", ""]]
    @Published var marks: [RowMark] = [.none, .none, .none]
    @Published var phase: Phase = .idle
    @Published var note: Note = .none
    @Published var noteText = ""
    @Published var shakes = 0
    /// The halves slide apart and Home rises behind them.
    @Published var ending = false
    /// True from the moment a check starts until the screen has left: the screen stays up while the account is already saved.
    @Published var isActive = false
    /// Which row shows the caret (debug captures draw a fixed one).
    @Published var staticFocus: Int? = nil
    /// A debug capture draws a fixed state and never calls the network.
    let frozen: Bool
    /// Set when a check starts: the screen keeps its "first launch" or "add" wording even after the account is saved.
    @Published var lockedAdd: Bool?
    private var run = 0

    init(frozen: Bool = false) { self.frozen = frozen }

    var rows: [String] {
        get { values[type] ?? ["", "", ""] }
        set { values[type] = newValue }
    }
    func set(_ i: Int, _ s: String) { var r = rows; r[i] = s; rows = r; if marks[i] == .bad { marks[i] = .none } }

    func clearResult() { marks = [.none, .none, .none]; note = .none; noteText = ""; if phase != .done { phase = .idle } }

    /// What the wait line says while a check runs.
    func waitText(xtreamLink: Bool) -> String {
        if xtreamLink { return "Recognised as an Xtream link: full library" }
        switch type { case .xtream: return "Contacting your server\u{2026}"; case .m3u: return "Reading your playlist\u{2026}"; case .portal: return "Contacting your portal\u{2026}" }
    }

    /// Checks the three rows and, when they pass, saves the source. `first` = the first source (the halves slide apart afterwards).
    func submit(catalog: Catalog, languages: [String], addMode: Bool, dismiss: @escaping () -> Void) {
        guard phase != .checking, !frozen else { return }
        let v = rows
        let missing = type.required.filter { v[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        if !missing.isEmpty {
            marks = [.none, .none, .none]
            for i in missing { marks[i] = .bad }
            note = .bad; noteText = type.needMessage; shakes += 1
            return
        }
        isActive = true; lockedAdd = addMode
        marks = [.none, .none, .none]
        phase = .checking
        let link = type == .m3u ? XtreamLink.parse(v[0]) : nil
        note = .wait; noteText = waitText(xtreamLink: link != nil)
        run += 1
        let mine = run, t = type
        Task {
            let out = await SourceChecker.check(t, v)
            guard mine == run else { return }
            if out.stage != .ok {
                let f = SourceChecker.failure(t, out.stage, xtreamLink: link != nil)
                marks = f.marks; note = .bad; noteText = f.message; phase = .idle; shakes += 1
                isActive = false; lockedAdd = nil
                return
            }
            marks = (0..<3).map { $0 == 0 || !v[$0].trimmingCharacters(in: .whitespaces).isEmpty ? .ok : .none }
            phase = .done; note = .ok
            noteText = addMode ? "Source added" : "Signed in \u{00B7} preparing your library"
            guard let acc = out.account else { return }
            if addMode {
                catalog.addAccount(acc)
                try? await Task.sleep(nanoseconds: 900_000_000)
                reset(); dismiss()
            } else {
                // Home loads for the new source while this screen is still up
                Task { await catalog.onboard(acc, languages: languages) }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                ending = true
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                reset(); dismiss()
            }
        }
    }

    func reset() {
        run += 1
        values = [.xtream: ["", "", ""], .m3u: ["", "", ""], .portal: ["", "", ""]]
        type = .xtream; marks = [.none, .none, .none]; note = .none; noteText = ""; phase = .idle; ending = false; isActive = false; lockedAdd = nil
    }

    /// The screen of this launch: a fixed capture state with -NXOnboardState (debug builds), else the live one.
    static func fromLaunch() -> OnboardingModel {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "NXOnboardState") {
            let t = SourceType(rawValue: UserDefaults.standard.string(forKey: "NXOnboardType") ?? "x") ?? .xtream
            return capture(state: s, type: t)
        }
        #endif
        return OnboardingModel()
    }

    // MARK: debug captures (never the network, never an account)

    /// -NXOnboardState idle|checking|error|success|home with -NXOnboardType x|m|p.
    static func capture(state: String, type t: SourceType) -> OnboardingModel {
        let m = OnboardingModel(frozen: true)
        m.type = t
        let fill: [SourceType: [String]] = [.xtream: ["http://media.example.net:8080", "alex.home", "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"],
                                            .m3u: ["https://lists.example.net/channels.m3u", "", "My playlist"],
                                            .portal: ["http://portal.example.net/c/", "00:1A:79:12:34:56", "My portal"]]
        switch state {
        case "idle": m.staticFocus = 0
        case "checking": m.values[t] = fill[t]!; m.phase = .checking; m.note = .wait; m.noteText = m.waitText(xtreamLink: false)
        case "error":
            m.values[t] = fill[t]!
            let f = SourceChecker.failure(t, t == .m3u ? .invalid : .auth)
            m.marks = f.marks; m.note = .bad; m.noteText = f.message
        case "success", "home":
            m.values[t] = fill[t]!
            m.marks = [.ok, fill[t]![1].isEmpty ? .none : .ok, .ok]; m.phase = .done; m.note = .ok; m.noteText = "Signed in \u{00B7} preparing your library"
            if state == "home" { m.ending = true }
        default: break
        }
        return m
    }
}
