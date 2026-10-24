import XCTest

/// Speed run: the app logs frame statistics and events (-NXMetrics YES); this test drives the remote through
/// fixed phases and writes their start/end times to $SHOTS_DIR/../perf-phases.txt. scripts/perf.py joins the two.
final class PerfTests: XCTestCase {
    let r = XCUIRemote.shared
    var lines: [String] = []
    func stamp(_ s: String) { lines.append(String(format: "%.3f ", Date().timeIntervalSince1970) + s) }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, gap: Double = 0.3) { for _ in 0..<n { r.press(b); idle(gap) } }

    func testSpeedRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-NXMetrics", "YES", "-NXTab", "home", "-NXResetLayout", "YES"] + (ProcessInfo.processInfo.environment["NX_PERF_ARGS"] ?? "").split(separator: " ").map(String.init)
        stamp("launch-pressed")
        app.launch()
        idle(15)
        // 1. focus moves along Home rows
        press(.down); idle(1)
        press(.down); idle(1)
        stamp("home-focus start")
        press(.right, 20, gap: 0.25)
        press(.down); press(.left, 10, gap: 0.25)
        press(.down); press(.right, 10, gap: 0.25)
        press(.down); press(.right, 10, gap: 0.25)
        stamp("home-focus end")
        idle(2)
        // 2. tab switches (first visit, then a second round)
        press(.menu); idle(2)
        let dir0 = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir0 + "/perf-after-menu.png"))
        for round in 1...2 {
            for t in ["live", "films", "series", "mylist", "search"] {
                stamp("switch \(round) \(t)")
                press(.right); idle(4)
            }
            press(.left, 5); idle(3)
        }
        // 3. focus moves in the Live TV channel list
        press(.right); idle(4)
        press(.down, 2); press(.right); idle(2)
        stamp("guide-focus start")
        press(.down, 20, gap: 0.25)
        stamp("guide-focus end")
        idle(2)
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try? lines.joined(separator: "\n").write(toFile: dir + "/../perf-phases.txt", atomically: true, encoding: .utf8)
    }
}
