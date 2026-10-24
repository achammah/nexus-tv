// Prints every normal window of a running app: id x y width height title (one per line).
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
for w in CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [] where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    guard let b = w[kCGWindowBounds as String] as? [String: Any], let n = w[kCGWindowNumber as String] else { continue }
    let width = (b["Width"] as? Double) ?? 0
    if width < 200 { continue }
    print(n, b["X"] ?? 0, b["Y"] ?? 0, width, b["Height"] ?? 0, (w[kCGWindowName as String] as? String) ?? "")
}
