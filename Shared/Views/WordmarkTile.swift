import SwiftUI

/// "B - Wordmark": a channel without a logo shows its cleaned name in bold capitals on soft glass tinted by a hue
/// taken from the name (the same channel has the same colour everywhere); the quality is a small badge top right.
struct WordmarkTile: View {
    let name: String
    let w: CGFloat, h: CGFloat
    var radius: CGFloat = 10

    static func hue(_ s: String) -> Double {
        var h = 0
        for u in s.unicodeScalars { h = (h * 31 + Int(u.value)) % 360 }
        return Double(h)
    }

    var body: some View {
        let p = LogoName.parse(name)
        let shown = p.name.isEmpty ? name : p.name
        let hue = Self.hue(shown) / 360
        let k = h / 108                       // the design is drawn on a 190 x 108 tile
        ZStack {
            RadialGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.40).opacity(0.9), Color(red: 27 / 255, green: 27 / 255, blue: 32 / 255)],
                           center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: max(w, h) * 0.9)
            Text(shown.uppercased())
                .font(.system(size: 19 * k, weight: .heavy)).lineSpacing(0).multilineTextAlignment(.center)
                .minimumScaleFactor(0.5).lineLimit(3).foregroundStyle(.white)
                .padding(.horizontal, 14 * k)
            if let q = p.quality {
                Text(q).font(.system(size: 9.5 * k, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6 * k).padding(.vertical, 2 * k)
                    .background(RoundedRectangle(cornerRadius: 5 * k).fill(Color.white.opacity(0.16)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8 * k)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityElement().accessibilityLabel(shown)
    }
}

/// What a channel tile knows about its logo.
enum ResolvedLogo { case loading, image(CGImage), none }

/// Resolves a channel's logo (own, twin, iptv-org) and hands the state to the tile to draw.
struct ChannelLogoResolver<Content: View>: View {
    let name: String, icon: String, sub: String
    var maxPixel: CGFloat = 300
    @ViewBuilder var content: (ResolvedLogo) -> Content
    @EnvironmentObject private var catalog: Catalog
    @State private var state = ResolvedLogo.loading
    var body: some View {
        content(state)
            .task(id: "\(name)|\(icon)|\(catalog.liveIndex.count)") {
                let logos = ChannelLogos.shared
                if let u = Img.url(icon), let c = ImageLoader.shared.cached(u, maxPixel: maxPixel) { state = .image(c); return }
                let index = catalog.liveIndex
                await Task.detached(priority: .utility) { logos.ensureTwins(index) }.value
                // no own logo and no twin: the wordmark shows at once; iptv-org may still replace it
                if icon.isEmpty, logos.twin(forKey: LogoName.parse(name).key, excluding: icon) == nil { state = .none }
                let cg = await logos.resolve(name: name, icon: icon, sub: sub, maxPixel: maxPixel)
                if let cg { state = .image(cg) } else { state = .none }
                #if DEBUG
                if ImageLoader.logOn { Metrics.shared.mark("logo \(cg == nil ? "none" : "image") own=\(icon.isEmpty ? 0 : 1) \(name.prefix(0))") }
                #endif
            }
    }
}
