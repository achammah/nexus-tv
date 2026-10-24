import XCTest
import SwiftUI
@testable import NexusTVMac

/// The opening's numbers and its rest frame, checked off screen (no mouse, no keyboard).
@MainActor
final class OpeningTests: XCTestCase {
    /// RGBA pixels of one opening frame drawn at 960 x 540.
    private func frame(_ f: Double) -> (px: [UInt8], w: Int, h: Int) {
        let r = ImageRenderer(content: OpeningFrame(frame: f).frame(width: 960, height: 540))
        r.scale = 1
        guard let cg = r.cgImage else { XCTFail("no render"); return ([], 0, 0) }
        let w = cg.width, h = cg.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (out, w, h)
    }
    private func pixel(_ p: (px: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * p.w + x) * 4
        return (Int(p.px[i]), Int(p.px[i + 1]), Int(p.px[i + 2]))
    }

    /// The spec's layout: rest lockup centred, about a quarter of the frame wide, the hinge at the mark's right edge.
    func testSpecGeometry() {
        XCTAssertEqual(OpeningSpec.tvSize, 272)
        XCTAssertEqual(OpeningSpec.gap, 93)
        XCTAssertEqual(OpeningSpec.lockW / OpeningSpec.w, 0.265, accuracy: 0.005)
        XCTAssertEqual(OpeningSpec.hinge, OpeningSpec.markW * 0.97, accuracy: 0.001)
        XCTAssertEqual(OpeningSpec.nCards, 10)
    }

    /// The timing curves end where the spec says: camera 4.5x to 1x over 32 frames, a card's swing 180 to 0 over 24.
    func testCurves() {
        XCTAssertEqual(OpeningEase.interp(0, 0, 32, 4.5, 1, OpeningEase.camera), 4.5, accuracy: 0.0001)
        XCTAssertEqual(OpeningEase.interp(32, 0, 32, 4.5, 1, OpeningEase.camera), 1, accuracy: 0.0001)
        XCTAssertEqual(OpeningEase.interp(12, 0, 24, 180, 0, OpeningEase.swing), 180 - 180 * OpeningEase.swing(0.5), accuracy: 0.0001)
        // cubic-bezier(0.62, 0.02, 0.22, 1) at its midpoint is past half (the whip through 90)
        XCTAssertGreaterThan(OpeningEase.swing(0.5), 0.5)
        XCTAssertEqual(OpeningEase.quadInOut(0.5), 0.5, accuracy: 0.0001)
    }

    /// Frame 0 is black (card one is still transparent); the rest frame shows the pearl mark and the "tv" at the centre.
    func testFirstAndRestFrames() {
        let f0 = frame(0)
        var lit = 0
        for i in stride(from: 0, to: f0.px.count, by: 4) where Int(f0.px[i]) + Int(f0.px[i + 1]) + Int(f0.px[i + 2]) > 30 { lit += 1 }
        XCTAssertLessThan(lit, 50, "frame 0 is black")
        let rest = frame(55)
        // the mark sits left of centre, the "tv" right of it (the spec's frame at half size)
        func bright(_ x0: CGFloat, _ x1: CGFloat) -> Int {
            var n = 0
            for y in Int(OpeningSpec.y0 / 2)..<Int((OpeningSpec.y0 + OpeningSpec.markH) / 2) {
                for x in Int(x0 / 2)..<Int(x1 / 2) { let c = pixel(rest, x, y); if c.0 + c.1 + c.2 > 600 { n += 1 } }
            }
            return n
        }
        let mark = bright(OpeningSpec.x0, OpeningSpec.x0 + OpeningSpec.markW)
        let tv = bright(OpeningSpec.x0 + OpeningSpec.tvX, OpeningSpec.x0 + OpeningSpec.lockW)
        XCTAssertGreaterThan(mark, 2000, "pearl mark at rest (bright pixels in the mark's box)")
        XCTAssertGreaterThan(tv, 1500, "tv at rest (bright pixels in the tv's box)")
        let corner = pixel(rest, 20, 20)
        XCTAssertLessThan(corner.0 + corner.1 + corner.2, 10, "black around the lockup")
    }

    /// Tests and screenshots (any -NX argument) start without the opening, so their first press is never eaten.
    func testGateOffUnderTestArguments() {
        XCTAssertEqual(OpeningGate.enabled, !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-NX") } || OpeningGate.frozenFrame != nil)
    }
}
