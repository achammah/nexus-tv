import SwiftUI
import UIKit

// MARK: - Look (values from the Frame app's css/app.css; 1 CSS px = 1 tvOS point at 1920x1080)

enum Theme {
    static let red = Color(red: 1, green: 0x3B / 255.0, blue: 0x4E / 255.0)
    static let tile = Color(red: 0x23 / 255.0, green: 0x26 / 255.0, blue: 0x2E / 255.0)
    static let logoBg = Color(red: 0x2A / 255.0, green: 0x2D / 255.0, blue: 0x36 / 255.0)
    static let glass = Color(red: 20 / 255.0, green: 20 / 255.0, blue: 24 / 255.0).opacity(0.62)
    static let stroke = Color.white.opacity(0.16)
    static let gold = Color(red: 1, green: 0xC9 / 255.0, blue: 0x4D / 255.0)
    static let ease = Animation.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.18)
    static let x0: CGFloat = 112
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// The frosted panel used by the guide, library and settings columns.
struct Glass: View {
    var radius: CGFloat = 28
    var body: some View {
        // a flat fill: the panels sit on black, so a blur behind them cost GPU time and showed nothing
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(red: 0.055, green: 0.055, blue: 0.066))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.ui(17, .bold)).tracking(2.4).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
    }
}

struct LivePill: View {
    var body: some View {
        Text("LIVE").font(.ui(16, .bold)).tracking(0.6).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Theme.red))
    }
}

// MARK: - Remote images: the shared loader (Shared/Core/ImageLoader.swift), name tile when missing

/// Apple TV wrapper over the shared loader; kept for BannerCard.
final class ImageStore {
    static let shared = ImageStore()
    func cached(_ url: URL, maxPixel: CGFloat = 600) -> UIImage? {
        ImageLoader.shared.cached(url, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
    }
    func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        await ImageLoader.shared.image(url, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
    }
}

struct RemoteImage<Fallback: View>: View {
    let url: URL?
    var maxPixel: CGFloat = 600
    var mode: ContentMode = .fill
    @ViewBuilder var fallback: () -> Fallback
    @State private var image: CGImage?

    var body: some View {
        let _ = Metrics.shared.count("RemoteImage")
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: mode).transition(.opacity)
            } else {
                fallback()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImageLoader.shared.cached(url, maxPixel: maxPixel) { image = c; return }
            image = nil
            let i = await ImageLoader.shared.image(url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.12)) { image = i }
            // a failed picture is tried again once the loader has forgotten the failure
            if i == nil, (try? await Task.sleep(for: .seconds(62))) != nil { image = await ImageLoader.shared.image(url, maxPixel: maxPixel) }
        }
    }
}

// MARK: - Focus styles (tuned to the Frame app, not stock tvOS)

/// .btn: frosted capsule, white when focused, scale 1.06.
struct PillButtonStyle: ButtonStyle {
    var height: CGFloat = 60
    var font: CGFloat = 24
    var hPad: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, height: height, font: font, hPad: hPad) }
    struct Face: View {
        let configuration: Configuration
        let height: CGFloat, font: CGFloat, hPad: CGFloat
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.ui(font, .semibold)).lineLimit(1)
                .padding(.horizontal, hPad).frame(height: height)
                .foregroundStyle(focused ? Color.black : Color.white)
                .background(Capsule().fill(focused ? Color.white : Theme.glass))
                .overlay(Capsule().stroke(focused ? Color.white : Theme.stroke, lineWidth: 1))
                .scaleEffect(focused ? (configuration.isPressed ? 1.0 : 1.06) : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

/// .li / .ctry / .season / menu items: plain, "on" when selected, white when focused.
struct ChipButtonStyle: ButtonStyle {
    var selected = false
    var height: CGFloat = 58
    var radius: CGFloat = 14
    var font: CGFloat = 23
    var hPad: CGFloat = 18
    var idle = Color.clear
    var onFill = Color.white.opacity(0.12)
    var dim = 0.66
    var scale: CGFloat = 1
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, s: self) }
    struct Face: View {
        let configuration: Configuration
        let s: ChipButtonStyle
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.ui(s.font, focused || s.selected ? .semibold : .regular)).lineLimit(1)
                .padding(.horizontal, s.hPad).frame(height: s.height)
                .foregroundStyle(focused ? Color.black : (s.selected ? Color.white : Color.white.opacity(s.dim)))
                .background(RoundedRectangle(cornerRadius: s.radius, style: .continuous).fill(focused ? Color.white : (s.selected ? s.onFill : s.idle)))
                .contentShape(RoundedRectangle(cornerRadius: s.radius, style: .continuous))
                .scaleEffect(focused ? s.scale : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

/// .tile: 14 pt corners, lifts 8 pt and scales 1.1 with a 4 pt white ring when focused.
struct TileButtonStyle: ButtonStyle {
    var radius: CGFloat = 14
    var scale: CGFloat = 1.1
    var lift: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, radius: radius, scale: scale, lift: lift) }
    struct Face: View {
        let configuration: Configuration
        let radius: CGFloat, scale: CGFloat, lift: CGFloat
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius + 3, style: .continuous).stroke(Color.white, lineWidth: focused ? 4 : 0).padding(-3))
                .shadow(color: .black.opacity(focused ? 0.75 : 0), radius: focused ? 18 : 0, y: focused ? 16 : 0)   // one shadow, on the focused tile only
                .scaleEffect(focused ? (configuration.isPressed ? scale - 0.04 : scale) : 1)
                .offset(y: focused ? -lift : 0)
                .zIndex(focused ? 3 : 0)
                .animation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.16), value: focused)
        }
    }
}

// MARK: - Tiles

enum TileShape { case poster, logo }

/// A picture tile; the name shows on the tile until (or unless) the picture loads.
struct TileFace: View {
    @EnvironmentObject var user: UserStore
    let item: MediaItem
    let shape: TileShape
    let w: CGFloat, h: CGFloat
    var progress: Double? = nil
    var fav = false
    var body: some View {
        let _ = Metrics.shared.count("TileFace")
        ZStack(alignment: .bottomLeading) {
            Theme.tile
            if shape == .logo {
                ChannelLogoResolver(name: item.name, icon: item.img, sub: item.sub, maxPixel: 400) { logo in
                    switch logo {
                    case .image(let cg): Image(decorative: cg, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                            .padding(.horizontal, w * 0.18).padding(.vertical, h * 0.14)
                    case .loading: Color.clear
                    case .none: WordmarkTile(name: item.name, w: w, h: h, radius: 0)
                    }
                }
            } else {
                RemoteImage(url: Img.url(item.img, .poster), maxPixel: 500, mode: .fill) { nameLabel }
                    .frame(width: w, height: h).clipped()
            }
            if let p = progress, p > 0 {
                Rectangle().fill(Theme.red).frame(width: w * p, height: 6)
            }
            if shape == .poster && item.kind != .live && user.hasSubs(item) {
                Text("CC").font(.ui(15, .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(10)
            }
            if let l = item.lang {
                Text(l).font(.ui(15, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.red.opacity(0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
            }
            if fav {
                Image(systemName: "star.fill").font(.ui(20, .bold)).foregroundStyle(Theme.gold)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
            }
        }
        .frame(width: w, height: h)
    }
    private var nameLabel: some View {
        Text(item.name)
            .font(.ui(shape == .logo ? 24 : 22, .bold)).foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center).lineLimit(shape == .logo ? 1 : 4).minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shape == .logo ? .center : .bottom)
            .padding(.bottom, shape == .logo ? 0 : 20)
    }
}

/// Channel logo box with the initials underneath (.ch .lg / .prev .big).
struct LogoBox: View {
    let name: String, icon: String
    let w: CGFloat, h: CGFloat
    var radius: CGFloat = 10
    var font: CGFloat = 17
    var body: some View {
        ZStack {
            Theme.logoBg
            ChannelLogoResolver(name: name, icon: icon, sub: "", maxPixel: 300) { logo in
                switch logo {
                case .image(let cg): Image(decorative: cg, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                        .padding(.horizontal, w * 0.08).padding(.vertical, h * 0.08)
                case .loading: Color.clear
                case .none: WordmarkTile(name: name, w: w, h: h, radius: 0)
                }
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Spinner: View {
    @State private var turn = false
    var body: some View {
        Circle().trim(from: 0, to: 0.75).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .background(Circle().stroke(Color.white.opacity(0.18), lineWidth: 3))
            .frame(width: 48, height: 48)
            .rotationEffect(.degrees(turn ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turn = true } }
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View { Text(text).font(.ui(26)).foregroundStyle(.white.opacity(0.5)) }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text).font(.ui(24)).padding(.horizontal, 30).padding(.vertical, 16)
            .background(Capsule().fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.85)))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

/// Facts line: "2025 · Drama · ★ 8".
struct Facts: View {
    let parts: [String]
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                if i > 0 { Text("·").foregroundStyle(.white.opacity(0.35)) }
                Text(p)
            }
        }
        .font(.ui(size)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
    }
}

// MARK: - Loading placeholders (soft sweep), shown at once while data loads

struct Skeleton: View {
    var radius: CGFloat = 14
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    LinearGradient(colors: [.clear, Color.white.opacity(0.09), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width * 1.3)
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct SkeletonRow: View {
    let w: CGFloat, h: CGFloat
    var gap: CGFloat = 26
    var count = 8
    var body: some View {
        HStack(spacing: gap) { ForEach(0..<count, id: \.self) { _ in Skeleton().frame(width: w, height: h) } }
    }
}

/// iOS-style wiggle for tiles being moved.
struct Jiggle: ViewModifier {
    let on: Bool
    let seed: Int
    @State private var tilt = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (tilt ? 1.6 : -1.6) * (seed % 2 == 0 ? 1 : -1) : 0))
            .animation(on ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: tilt)
            .onAppear { if on { tilt.toggle() } }
            .onChange(of: on) { _, v in if v { tilt.toggle() } }
    }
}
