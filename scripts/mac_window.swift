// Prints the window id of a running app's window whose title contains the given text (or its largest window).
// Usage: swift scripts/mac_window.swift <pid> [title text]
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let want = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0 }
let pick = mine.filter { want.isEmpty || (($0[kCGWindowName as String] as? String) ?? "").contains(want) }
    .max { a, b in
        let wa = ((a[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0
        let wb = ((b[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0
        return wa < wb
    }
if let p = pick, let n = p[kCGWindowNumber as String] { print(n) } else { exit(1) }
