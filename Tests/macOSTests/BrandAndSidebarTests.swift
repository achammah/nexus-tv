import XCTest
import SwiftUI
@testable import NexusTVMac

/// Rendered checks (no mouse, no keyboard): views are drawn off screen with ImageRenderer and their pixels read.
@MainActor
final class BrandAndSidebarTests: XCTestCase {
    private func pixels(_ v: some View, width: CGFloat = 216, height: CGFloat = 30) -> [UInt8] {
        let r = ImageRenderer(content: v.frame(width: width, height: height).background(MacTheme.sidebar).environment(\.colorScheme, .dark))
        r.scale = 2
        guard let cg = r.cgImage else { XCTFail("no render"); return [] }
        let w = cg.width, h = cg.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out
    }
    /// How many pixels differ between two renders.
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return Int.max }
        var n = 0
        for i in stride(from: 0, to: a.count, by: 4) where abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 60 { n += 1 }
        return n
    }

    /// The selected country row: its code and its count must be visible on the white selection.
    func testSelectedCountryRowShowsCodeAndCount() {
        let full = pixels(CountrySideRow(code: "BE", name: "Belgium", flag: nil, count: "542", selected: true) {})
        let noCode = pixels(CountrySideRow(code: "", name: "Belgium", flag: nil, count: "542", selected: true) {})
        let noCount = pixels(CountrySideRow(code: "BE", name: "Belgium", flag: nil, count: "", selected: true) {})
        XCTAssertGreaterThan(changed(full, noCode), 40, "the code BE shows on the selected row")
        XCTAssertGreaterThan(changed(full, noCount), 40, "the count 542 shows on the selected row")
    }

    /// The header lockup is one image (mark and "tv" drawn together, so their sizes match) and it is not empty.
    func testHeaderLockupIsTheNewOne() {
        XCTAssertNotNil(NSImage(named: "Lockup"), "the Lockup asset is in the app")
        XCTAssertNil(NSImage(named: "NexusLogo"), "the old Nexus | TV parts are gone")
        let lit = pixels(Wordmark(), width: 120, height: 40)
        var bright = 0
        for i in stride(from: 0, to: lit.count, by: 4) where Int(lit[i]) + Int(lit[i + 1]) + Int(lit[i + 2]) > 500 { bright += 1 }
        XCTAssertGreaterThan(bright, 200, "the lockup draws")
    }
}
