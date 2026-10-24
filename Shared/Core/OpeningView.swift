import SwiftUI
import CoreText
import QuartzCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The opening, drawn natively from vectors (crisp at any size): ten glass cards of the mark and "tv" swing
/// around a hinge at the mark's right edge, the camera pulls back from 4.5x, a pearl plate seals the stack.
/// Every number comes from the motion spec (logo/remotion/src/Opening.tsx), in its 1920 x 1080 frame.
enum OpeningSpec {
    static let w: CGFloat = 1920, h: CGFloat = 1080
    static let markH: CGFloat = 216
    static let markW: CGFloat = markH * 242 / 280
    static let tvSize: CGFloat = (markH * 0.78 / 0.62).rounded()
    static let gap: CGFloat = (markW * 0.5).rounded()
    static let tvW: CGFloat = tvSize * 0.84
    static let lockW: CGFloat = markW + gap + tvW
    static let x0: CGFloat = (w - lockW) / 2, y0: CGFloat = (h - markH) / 2
    static let hinge: CGFloat = markW * 0.97
    static let tvX: CGFloat = markW + gap, tvBase: CGFloat = markH * 0.99
    static let cards: [(fill: Color, rim: Color)] = [
        (rgb(0x6A1BE0), rgb(0xFF4BE0)),   // purple / magenta
        (rgb(0x1A4FD6), rgb(0x3DDCFF)),   // navy / cyan
        (rgb(0x0F9A52), rgb(0x4DFF9E)),   // green / mint
        (rgb(0xD66A16), rgb(0xFFC15A)),   // orange / amber
        (rgb(0xCC1640), rgb(0xFF5C78)),   // red / coral
    ]
    static let nCards = 10
    static let offset: Double = 3.5, swing: Double = 24
    static let fps: Double = 30
    /// The whole opening lasts `duration`; it holds on black for `hold`, then Home fades in over `fadeOut`.
    static let duration: Double = 3, hold: Double = 0.3, fadeOut: Double = 0.5
    static var homeAt: Double { duration + hold }
    static let markPaths: [String] = [
        "M0 69.855L0.000167052 209.566L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855Z",
        "M164.313 77.4323C184.262 88.9537 196.551 110.246 196.551 133.289L196.551 183.37L241.909 209.566L241.909 107.093C241.909 84.0505 229.62 62.758 209.67 51.2365L120.955 9.45148e-06L120.955 52.3915L164.313 77.4323Z",
        "M103.836 112.36C123.785 123.881 136.074 145.174 136.074 168.217L136.074 218.298L181.432 244.494L181.432 142.021C181.432 118.978 169.143 97.6856 149.193 86.1641L60.4779 34.9276L60.478 87.3191L103.836 112.36Z",
        "M43.3578 147.287C63.307 158.809 75.5963 180.101 75.5963 203.144L75.5964 253.225L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855L7.91518e-05 122.247L43.3578 147.287Z",
    ]
    static func rgb(_ v: Int, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: a)
    }
}

/// Timing curves of the spec (Remotion's interpolate with clamp, Easing.bezier and Easing.inOut(quad)).
enum OpeningEase {
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func interp(_ f: Double, _ a: Double, _ b: Double, _ from: Double, _ to: Double, _ ease: (Double) -> Double) -> Double {
        from + (to - from) * ease(clamp01((f - a) / (b - a)))
    }
    static func quadInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
    /// CSS cubic-bezier(x1, y1, x2, y2): solve x(u) = t, return y(u).
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> (Double) -> Double {
        { t in
            if t <= 0 { return 0 }; if t >= 1 { return 1 }
            func c(_ u: Double, _ p1: Double, _ p2: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u }
            var lo = 0.0, hi = 1.0, u = t
            for _ in 0..<40 { u = (lo + hi) / 2; if c(u, x1, x2) < t { lo = u } else { hi = u } }
            return c(u, y1, y2)
        }
    }
    static let swing = bezier(0.62, 0.02, 0.22, 1)
    static let camera = bezier(0.45, 0, 0.15, 1)
}

/// The geometry, built once: the four mark paths and the "tv" glyphs, in the spec's 1920 x 1080 frame.
final class OpeningShapes {
    static let shared = OpeningShapes()
    /// Mark paths at rest (card space: the card's top-left at 0,0).
    let mark: [Path]
    /// "tv" as one path, in card space, and its text box (ascent to descent, for the gradient).
    let tv: Path
    let tvBox: CGRect

    private init() {
        let s = OpeningSpec.markH / 280
        mark = OpeningSpec.markPaths.map { OpeningShapes.parse($0).applying(CGAffineTransform(scaleX: s, y: s)) }
        let size = OpeningSpec.tvSize
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: size, weight: .medium) as CTFont
        #else
        let font = NSFont.systemFont(ofSize: size, weight: .medium) as CTFont
        #endif
        var chars = Array("tv".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let spacing = -size * 0.015
        var p = Path(), x = OpeningSpec.tvX
        for (i, g) in glyphs.enumerated() {
            if let gp = CTFontCreatePathForGlyph(font, g, nil) {
                // glyphs are y-up: flip onto the baseline
                p.addPath(Path(gp), transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: OpeningSpec.tvBase))
            }
            x += advances[i].width + spacing
        }
        tv = p
        let asc = CTFontGetAscent(font), desc = CTFontGetDescent(font)
        tvBox = CGRect(x: OpeningSpec.tvX, y: OpeningSpec.tvBase - asc, width: x - spacing - OpeningSpec.tvX, height: asc + desc)
    }

    /// SVG path data with absolute M, L, C and Z (the mark file uses nothing else).
    static func parse(_ d: String) -> Path {
        var p = Path()
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if "MLCZ".contains(ch) { if !cur.isEmpty { tokens.append(cur) }; tokens.append(String(ch)); cur = "" }
            else if ch == " " || ch == "," { if !cur.isEmpty { tokens.append(cur) }; cur = "" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var i = 0, cmd = "M"
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if "MLCZ".contains(tokens[i]) { cmd = tokens[i]; i += 1; if cmd == "Z" { p.closeSubpath(); continue } }
            switch cmd {
            case "M": p.move(to: CGPoint(x: num(), y: num())); cmd = "L"
            case "L": p.addLine(to: CGPoint(x: num(), y: num()))
            case "C":
                let c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num()), e = CGPoint(x: num(), y: num())
                p.addCurve(to: e, control1: c1, control2: c2)
            default: i += 1
            }
        }
        return p
    }
}

/// One frame of the opening (frame = seconds x 30, fractional frames allowed), filling its frame on black.
struct OpeningFrame: View {
    let frame: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let k = min(size.width / OpeningSpec.w, size.height / OpeningSpec.h)
            let off = CGPoint(x: (size.width - OpeningSpec.w * k) / 2, y: (size.height - OpeningSpec.h * k) / 2)
            let cam = OpeningEase.interp(frame, 0, 32, 4.5, 1, OpeningEase.camera)
            let s = k * cam
            // canvas point p -> screen: off + k * (C + cam * (p - C)), C = the camera's pivot (48 %, 51 %)
            let c = CGPoint(x: OpeningSpec.w * 0.48, y: OpeningSpec.h * 0.51)
            let base = CGPoint(x: off.x + k * c.x * (1 - cam), y: off.y + k * c.y * (1 - cam))
            let toScreen = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: base.x + s * OpeningSpec.x0, ty: base.y + s * OpeningSpec.y0)
            let pivot = CGPoint(x: base.x + s * (OpeningSpec.x0 + OpeningSpec.hinge), y: base.y + s * (OpeningSpec.y0 + OpeningSpec.markH / 2))
            let eye = CGPoint(x: base.x + s * OpeningSpec.w / 2, y: base.y + s * OpeningSpec.h / 2)
            let tvCard = OpeningEase.interp(frame, 11, 24, 0, 1, OpeningEase.quadInOut)
            ZStack {
                Color.black
                ForEach(0..<OpeningSpec.nCards, id: \.self) { i in
                    let start = Double(i) * OpeningSpec.offset
                    if frame >= start {
                        let rot = OpeningEase.interp(frame - start, 0, OpeningSpec.swing, 180, 0, OpeningEase.swing)
                        let op = OpeningEase.interp(frame - start, 0, 12, 0, 1, OpeningEase.quadInOut)
                        let colors = OpeningSpec.cards[i % OpeningSpec.cards.count]
                        OpeningCard(fill: colors.fill, rim: colors.rim, toScreen: toScreen, scale: s, light: s * cam,
                                    tvOpacity: rot < 90 ? tvCard : 0)
                            .projectionEffect(OpeningFrame.swing(rot, pivot: pivot, eye: eye, distance: 1100 * s))
                            .opacity(op)
                            .blendMode(.screen)
                    }
                }
                OpeningPlate(toScreen: toScreen,
                             plate: OpeningEase.interp(frame, 16, 34, 0, 1, OpeningEase.quadInOut),
                             tv: OpeningEase.interp(frame, 22, 36, 0, 1, OpeningEase.quadInOut))
            }
            .compositingGroup()
        }
        .background(Color.black)
    }

    /// CSS rotateY(deg) about the hinge, seen through perspective `distance` from `eye` (row-vector order).
    static func swing(_ deg: Double, pivot: CGPoint, eye: CGPoint, distance: CGFloat) -> ProjectionTransform {
        let a = deg * .pi / 180
        var r = CATransform3DIdentity
        r.m11 = CGFloat(cos(a)); r.m31 = CGFloat(sin(a)); r.m13 = CGFloat(-sin(a)); r.m33 = CGFloat(cos(a))
        var p = CATransform3DIdentity
        p.m34 = -1 / distance
        var m = CATransform3DMakeTranslation(-pivot.x, -pivot.y, 0)
        m = CATransform3DConcat(m, r)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(pivot.x - eye.x, pivot.y - eye.y, 0))
        m = CATransform3DConcat(m, p)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(eye.x, eye.y, 0))
        return ProjectionTransform(m)
    }
}

/// A glass card: 55 % fill, a soft 7 pt inner light along the edge, a 1.6 pt rim and its 2 pt halo.
/// In the reference render the inner light grows with the camera zoom (at 4x it fills the card), so `light` is
/// the screen scale times the camera; at rest it equals `scale` and matches the spec's numbers.
private struct OpeningCard: View {
    let fill: Color, rim: Color
    let toScreen: CGAffineTransform
    let scale: CGFloat, light: CGFloat
    let tvOpacity: Double

    var body: some View {
        Canvas { ctx, _ in
            let shapes = OpeningShapes.shared
            var mark = Path()
            for p in shapes.mark { mark.addPath(p) }
            glass(&ctx, mark.applying(toScreen))
            if tvOpacity > 0 {
                var t = ctx
                t.opacity = tvOpacity
                t.drawLayer { l in glass(&l, shapes.tv.applying(toScreen)) }
            }
        }
    }

    private func glass(_ ctx: inout GraphicsContext, _ path: Path) {
        let s = scale
        ctx.fill(path, with: .color(fill.opacity(0.55)))
        ctx.drawLayer { outer in                       // inner light: a 7 pt band inside the edge, blurred, kept inside
            outer.clip(to: path)
            outer.drawLayer { band in
                band.addFilter(.blur(radius: 4 * light))
                band.stroke(path, with: .color(rim.opacity(0.55)), lineWidth: 14 * light)
            }
        }
        ctx.drawLayer { halo in                        // halo: the rim, blurred (it spills past the edge)
            halo.addFilter(.blur(radius: 2 * s))
            halo.drawLayer { ring in ring.clip(to: path); ring.stroke(path, with: .color(rim), lineWidth: 3.2 * s) }
        }
        ctx.drawLayer { ring in ring.clip(to: path); ring.stroke(path, with: .color(rim), lineWidth: 3.2 * s) }
    }
}

/// The pearl plate (white to #F3E7F7 to #D394E6, with a white sheen from the top right) and the "tv" (white to
/// #AEDB8E), each gradient laid in its own shape's box like SVG's objectBoundingBox.
private struct OpeningPlate: View {
    let toScreen: CGAffineTransform
    let plate: Double, tv: Double

    var body: some View {
        Canvas { ctx, _ in
            let shapes = OpeningShapes.shared
            let pearl = Gradient(stops: [.init(color: OpeningSpec.rgb(0xFDFEFF), location: 0),
                                         .init(color: OpeningSpec.rgb(0xF3E7F7), location: 0.5),
                                         .init(color: OpeningSpec.rgb(0xD394E6), location: 1)])
            let sheen = Gradient(stops: [.init(color: OpeningSpec.rgb(0xFFFFFF, 0.9), location: 0),
                                         .init(color: OpeningSpec.rgb(0xC6B8C5, 0), location: 1)])
            let tvg = Gradient(stops: [.init(color: OpeningSpec.rgb(0xFEFEFE), location: 0),
                                       .init(color: OpeningSpec.rgb(0xF4F7EE), location: 0.55),
                                       .init(color: OpeningSpec.rgb(0xAEDB8E), location: 1)])
            if plate > 0 {
                var g = ctx
                g.opacity = plate
                g.drawLayer { l in
                    for m in shapes.mark {
                        let p = m.applying(toScreen)
                        boxFill(&l, p, p.boundingRect, pearl, CGPoint(x: 0, y: 0), CGPoint(x: 0.35, y: 1))
                        boxFill(&l, p, p.boundingRect, sheen, CGPoint(x: 1, y: 0), CGPoint(x: 0.4, y: 1))
                    }
                }
            }
            if tv > 0 {
                var g = ctx
                g.opacity = tv
                let p = shapes.tv.applying(toScreen)
                boxFill(&g, p, shapes.tvBox.applying(toScreen), tvg, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1))
            }
        }
    }

    /// Fill `path` with a linear gradient whose ends are given in the unit square of `box`.
    private func boxFill(_ ctx: inout GraphicsContext, _ path: Path, _ box: CGRect, _ g: Gradient, _ a: CGPoint, _ b: CGPoint) {
        var c = ctx
        c.clip(to: path)
        c.concatenate(CGAffineTransform(a: box.width, b: 0, c: 0, d: box.height, tx: box.minX, ty: box.minY))
        c.fill(Path(CGRect(x: -0.5, y: -0.5, width: 2, height: 2)), with: .linearGradient(g, startPoint: a, endPoint: b))
    }
}

/// The opening on a clock: plays once from appearance; `frozen` holds one frame (screenshots and tests).
struct OpeningView: View {
    var frozen: Double? = nil
    @State private var start = Date()

    var body: some View {
        if let frozen {
            OpeningFrame(frame: frozen)
        } else {
            TimelineView(.animation) { tl in
                let f = min(OpeningSpec.duration, tl.date.timeIntervalSince(start)) * OpeningSpec.fps
                OpeningFrame(frame: f)
            }
        }
    }
}

/// When the opening shows: on every launch, except under test or screenshot launch arguments (any -NX… other
/// than -NXOpening YES), and -NXOpeningFrame N holds frame N.
enum OpeningGate {
    static var frozenFrame: Double? {
        UserDefaults.standard.string(forKey: "NXOpeningFrame").flatMap(Double.init)
    }
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-NXOpening") { return UserDefaults.standard.bool(forKey: "NXOpening") }
        if frozenFrame != nil { return true }
        return !args.contains { $0.hasPrefix("-NX") }
    }
}

/// The launch overlay: the opening over a Home that loads underneath (a ready Home is never held back). Home
/// fades in after the animation ends and holds on black; any press, click or key skips. `onFinish` removes the overlay.
struct OpeningOverlay: View {
    let onFinish: () -> Void
    @State private var shown = 1.0
    @State private var done = false
    #if os(macOS)
    @State private var monitor: Any?
    #endif

    var body: some View {
        let frozen = OpeningGate.frozenFrame
        Button(action: skip) { OpeningView(frozen: frozen).ignoresSafeArea() }
            .buttonStyle(OpeningPress())
            .opacity(shown)
            .accessibilityIdentifier("opening")
            #if os(tvOS)
            .onMoveCommand { _ in skip() }
            .onExitCommand { skip() }
            .onPlayPauseCommand { skip() }
            #endif
            .task {
                guard frozen == nil else { return }
                // the animation plays to its end, holds on black, then black fades to Home
                try? await Task.sleep(nanoseconds: UInt64(OpeningSpec.homeAt * 1e9))
                guard !done else { return }
                withAnimation(.easeInOut(duration: OpeningSpec.fadeOut)) { shown = 0 }
                try? await Task.sleep(nanoseconds: UInt64(OpeningSpec.fadeOut * 1e9))
                finish()
            }
            #if os(macOS)
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { _ in
                    if OpeningGate.frozenFrame == nil { skip() }
                    return nil
                }
            }
            .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
            #endif
    }

    private func skip() {
        guard !done, OpeningGate.frozenFrame == nil else { return }
        withAnimation(.easeOut(duration: 0.25)) { shown = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { finish() }
    }

    private func finish() {
        guard !done else { return }
        done = true
        #if os(macOS)
        if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil
        #endif
        onFinish()
    }
}

/// The opening as a button: no focus ring, no lift.
private struct OpeningPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
