import Foundation
import QuartzCore

/// Speed measurements, on only with the launch argument -NXMetrics YES.
/// Writes lines to Caches/nexus/metrics.log: "<unix seconds> <event>" and, every second, frame statistics from a
/// display link (frames drawn, hitches over 25 ms, longest frame) and main-thread load from a run-loop observer
/// (milliseconds the main thread was busy, longest single busy stretch). The busy time is the CPU cost that a
/// slower Apple TV multiplies; the frame counts alone hide it on a fast Mac. Host and simulator share a clock,
/// so a UI test can cut the log into windows by its own timestamps.
final class Metrics: NSObject {
    static let shared = Metrics()
    static let on = UserDefaults.standard.bool(forKey: "NXMetrics")
    let launch = Date()
    private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("metrics.log")
    private let q = DispatchQueue(label: "metrics")
    #if os(tvOS)
    private var link: CADisplayLink?
    #endif
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0
    private var worst: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var marked = Set<String>()
    private var busy: CFTimeInterval = 0, longest: CFTimeInterval = 0, wake: CFTimeInterval = 0
    private var observer: CFRunLoopObserver?

    func start() {
        guard Self.on else { return }
        try? FileManager.default.removeItem(at: url)
        write("launch")
        let o = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, act in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if act == .afterWaiting { self.wake = now }
            else if self.wake > 0 { let d = now - self.wake; self.busy += d; self.longest = max(self.longest, d); self.wake = 0 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        observer = o
        #if os(tvOS)
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        #endif
    }

    /// View body evaluations, per view type, logged with the frame line each second.
    private var bodies: [String: Int] = [:]
    @inline(__always) func count(_ view: String) { if Self.on { bodies[view, default: 0] += 1 } }

    /// An event; with `once`, only its first occurrence is kept (e.g. "first home frame").
    func mark(_ name: String, once: Bool = false) {
        guard Self.on else { return }
        if once { if marked.contains(name) { return }; marked.insert(name) }
        write(name + String(format: " +%.0fms", Date().timeIntervalSince(launch) * 1000))
    }

    #if os(tvOS)
    @objc private func tick(_ l: CADisplayLink) { frame(at: l.timestamp) }
    #endif
    private func frame(at t: CFTimeInterval) {
        if last > 0 {
            let d = t - last
            frames += 1
            if d > 0.025 { hitches += 1 }
            worst = max(worst, d)
        }
        last = t
        if windowStart == 0 { windowStart = t }
        if t - windowStart >= 1 {
            write(String(format: "frames %d hitches %d worst %.0fms busy %.0fms longest %.0fms", frames, hitches, worst * 1000, busy * 1000, longest * 1000)
                  + (bodies.isEmpty ? "" : " bodies " + bodies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")))
            bodies = [:]
            frames = 0; hitches = 0; worst = 0; busy = 0; longest = 0; windowStart = t
        }
    }

    private func write(_ s: String) {
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + s + "\n"
        q.async { [url] in
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.data(using: .utf8)!.write(to: url) }
        }
    }
}
