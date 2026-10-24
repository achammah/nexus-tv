import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The 3b "cinematic banner" list card, shared by the Mac and the Apple TV (sizes scale with its width).

/// A picture for card art: the Mac's or the TV's own image loader.
struct ArtImage: View {
    let url: URL?
    var fill = true
    var body: some View {
        #if os(macOS)
        MacImage(url: url, fill: fill) { Color.clear }
        #else
        RemoteImage(url: url, maxPixel: 400, mode: fill ? .fill : .fit) { Color.clear }
        #endif
    }
}

// MARK: - card

/// What a banner card shows. Art, in this order: a real logo, a collage of the list's own titles (posters, or
/// channel logos for Live), else type only.
struct BannerModel: Hashable {
    enum Art: Hashable { case logo(String, dark: Bool), posters([String]), channels([String]), type }
    var art: Art
    var name: String
    var count: Int?
    var unit: String
    /// The logo is the name (a service or network): the name rides in the small line instead of large type.
    var logoIsName = false
    /// A sublist keeps its service logo as a small badge.
    var badge: (url: String, dark: Bool)? = nil
    var muted = false
    static func == (a: BannerModel, b: BannerModel) -> Bool { a.art == b.art && a.name == b.name && a.count == b.count && a.badge?.url == b.badge?.url }
    func hash(into h: inout Hasher) { h.combine(name); h.combine(count) }

    var countText: String { count.map { Browse.count($0, unit) } ?? "" }
    /// The first picture: its colour tints the wash.
    var tintSource: String? {
        switch art { case .logo(let u, _): u; case .posters(let p): p.first; case .channels(let c): c.first; case .type: nil }
    }
}

/// The dominant colour of a picture, computed once per picture; greyscale art gets the neutral tint.
@MainActor
enum ArtTint {
    static let neutral = (r: 58.0 / 255, g: 61.0 / 255, b: 72.0 / 255)
    private static var cache: [URL: (r: Double, g: Double, b: Double)] = [:]
    static func tint(_ url: URL) async -> (r: Double, g: Double, b: Double) {
        if let c = cache[url] { return c }
        #if os(macOS)
        guard let img = await MacImages.shared.image(url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return neutral }
        #else
        guard let img = await ImageStore.shared.load(url, maxPixel: 96), let cg = img.cgImage else { return neutral }
        #endif
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 128 {
            let R = Double(px[i]) / 255, G = Double(px[i + 1]) / 255, B = Double(px[i + 2]) / 255
            let sat = max(R, G, B) - min(R, G, B)
            r += R * sat; g += G * sat; b += B * sat; w += sat
        }
        var out = neutral
        if w > 2 {       // enough coloured pixels; else the art is grey, black or white
            r /= w; g /= w; b /= w
            let m = max(r, g, b, 0.001), k = 0.88 / m        // bright enough to read as a colour, never white
            out = (min(1, r * k), min(1, g * k), min(1, b * k))
        }
        cache[url] = out
        return out
    }
}

private func mix(_ c: (r: Double, g: Double, b: Double), _ t: Double, with d: (Double, Double, Double) = (11 / 255, 11 / 255, 13 / 255)) -> Color {
    Color(red: c.r * t + d.0 * (1 - t), green: c.g * t + d.1 * (1 - t), blue: c.b * t + d.2 * (1 - t))
}

/// The 3b card: landscape 288 x 162 on the Mac (scaled for the TV), art full-bleed, colour wash from the left,
/// the name large inside. Every size scales with the width.
struct BannerCard: View {
    let model: BannerModel
    var width: CGFloat = 288
    let action: () -> Void
    @State private var tint = ArtTint.neutral
    @State private var hover = false
    private var k: CGFloat { width / 288 }

    var body: some View {
        let h = width * 162 / 288
        #if os(tvOS)
        Button(action: action) { face(h) }
            .buttonStyle(TileButtonStyle(radius: 12 * k, scale: 1.06, lift: 6))
            .accessibilityLabel(model.name + (model.countText.isEmpty ? "" : ", " + model.countText))
            .accessibilityIdentifier("card:" + model.name)
            .task(id: model.tintSource) { if let s = model.tintSource, let u = Img.url(s, .poster) { tint = await ArtTint.tint(u) } }
        #else
        Button(action: action) {
            face(h)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(hover ? 0.5 : 0.06), lineWidth: hover ? 2 : 1))
                .scaleEffect(hover ? 1.02 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.name + (model.countText.isEmpty ? "" : ", " + model.countText))
        .accessibilityIdentifier("card:" + model.name)
        .task(id: model.tintSource) { if let s = model.tintSource, let u = Img.url(s, .poster) { tint = await ArtTint.tint(u) } }
        #endif
    }

    private func face(_ h: CGFloat) -> some View {
            ZStack(alignment: .bottomLeading) {
                Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).zIndex(-2)
                art(h)
                wash
                if let b = model.badge {
                    ArtImage(url: URL(string: b.url), fill: false).frame(height: 18 * k)
                        .padding(.horizontal, 8 * k).padding(.vertical, 4 * k)
                        .background(RoundedRectangle(cornerRadius: 7 * k).fill(b.dark ? Color(white: 0.9) : Color.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12 * k)
                }
                VStack(alignment: .leading, spacing: 3 * k) {
                    Text(showName ? model.countText.uppercased() : ([model.name, model.countText].filter { !$0.isEmpty }.joined(separator: " · ")).uppercased())
                        .font(.system(size: 10.5 * k, weight: .bold)).tracking(0.6 * k).foregroundStyle(Color.white.opacity(0.75))
                    if showName {
                        Text(model.name).font(.system(size: (model.art == .type ? 28 : 19) * k, weight: .heavy)).tracking((model.art == .type ? -0.6 : -0.35) * k)
                            .lineLimit(2).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                            .frame(maxWidth: model.art == .type ? .infinity : 200 * k, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14 * k).padding(.bottom, 12 * k)
            }
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 12 * k))
            .opacity(model.muted ? 0.55 : 1)
    }

    private var showName: Bool { if case .logo = model.art, model.logoIsName { return false }; return true }

    @ViewBuilder private func art(_ h: CGFloat) -> some View {
        switch model.art {
        case .posters(let p):
            HStack(spacing: 0) {
                ForEach(Array(p.prefix(4).enumerated()), id: \.offset) { _, u in
                    ArtImage(url: Img.url(u, .poster)).frame(width: width / CGFloat(max(1, min(4, p.count))), height: h).clipped()
                }
            }
            .scaleEffect(1.04)
        case .channels(let c):
            LazyVGrid(columns: [GridItem(.fixed(82 * k), spacing: 6 * k), GridItem(.fixed(82 * k), spacing: 6 * k)], spacing: 6 * k) {
                ForEach(Array(c.prefix(6).enumerated()), id: \.offset) { _, u in
                    ArtImage(url: URL(string: u), fill: false)
                        .frame(width: 62 * k, height: 28 * k).frame(width: 82 * k, height: (h - 32 * k) / 3)
                        .background(RoundedRectangle(cornerRadius: 6 * k).fill(Color(red: 31 / 255, green: 33 / 255, blue: 40 / 255)))
                }
            }
            .frame(width: 170 * k).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(10 * k)
        case .logo(let u, let dark):
            ZStack {
                if dark {
                    RoundedRectangle(cornerRadius: 10 * k).fill(LinearGradient(colors: [Color(white: 0.953), Color(white: 0.863)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(EdgeInsets(top: 22 * k, leading: 50 * k, bottom: 40 * k, trailing: 50 * k))
                }
                ArtImage(url: URL(string: u), fill: false)
                    .frame(maxWidth: (dark ? 110 : 150) * k, maxHeight: (dark ? 46 : 62) * k)
                    .padding(.bottom, (dark ? 18 : 14) * k)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(2)
        case .type: EmptyView()
        }
    }

    @ViewBuilder private var wash: some View {
        switch model.art {
        case .posters:
            ZStack {
                LinearGradient(stops: [.init(color: mix(tint, 0.78), location: 0), .init(color: mix(tint, 1).opacity(0.55), location: 0.48),
                                       .init(color: .black.opacity(0.15), location: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.55)], startPoint: .bottom, endPoint: .top)
            }
        case .channels:
            LinearGradient(stops: [.init(color: mix(tint, 0.70), location: 0), .init(color: mix(tint, 0.45), location: 0.42),
                                   .init(color: .clear, location: 0.70)], startPoint: .leading, endPoint: .trailing)
        case .logo, .type:
            RadialGradient(stops: [.init(color: mix(tint, 0.45, with: (20 / 255, 20 / 255, 24 / 255)), location: 0),
                                   .init(color: Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255), location: 0.75)],
                           center: UnitPoint(x: 0.8, y: 0.2), startRadius: 0, endRadius: 330 * k)
                .zIndex(-1)
        }
    }
}

// MARK: - models from the catalogue

@MainActor
enum BannerModels {
    static func unit(_ kind: ItemKind) -> String { kind == .film ? "film" : kind == .series ? "series" : "channel" }

    static func list(_ l: Browse.List, kind: ItemKind, catalog: Catalog, label: String? = nil) -> BannerModel {
        let art = l.ids.flatMap { catalog.catArt[$0] ?? [] }
        return BannerModel(art: art.isEmpty ? .type : .posters(Array(art.prefix(4))), name: label ?? l.label, count: l.count, unit: unit(kind))
    }
    static func service(_ s: Browse.Service, lists: Int) -> BannerModel {
        BannerModel(art: s.logo.map { .logo($0, dark: s.dark) } ?? .type, name: s.name, count: lists, unit: "list", logoIsName: s.logo != nil)
    }
    static func sub(_ l: Browse.List, _ s: Browse.Service, kind: ItemKind, catalog: Catalog, label: String? = nil) -> BannerModel {
        var m = list(l, kind: kind, catalog: catalog, label: label ?? Browse.inService(l.label, s.name))
        if let logo = s.logo { m.badge = (logo, s.dark) }
        return m
    }
    static func live(_ l: Browse.List, catalog: Catalog) -> BannerModel {
        if let logo = Browse.liveLogos[l.label] {
            return BannerModel(art: .logo(logo, dark: false), name: l.label, count: l.count, unit: "channel", logoIsName: true, muted: l.muted)
        }
        if l.family == Browse.LiveFamily.ev.rawValue || l.family == Browse.LiveFamily.reg.rawValue {
            return BannerModel(art: .type, name: l.label, count: l.count, unit: "channel", muted: l.muted)
        }
        let logos = l.ids.flatMap { catalog.liveIndex[$0] ?? [] }.map(\.icon).filter { !$0.isEmpty }
        return BannerModel(art: logos.isEmpty ? .type : .channels(Array(logos.prefix(6))), name: l.label, count: l.count, unit: "channel", muted: l.muted)
    }
}
