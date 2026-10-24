import SwiftUI
import AppKit

/// The Nexus dark look on the Mac (layout 1a): near-black window, #17171a sidebar, white selection.
enum MacTheme {
    static let window = Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
    static let sidebar = Color(red: 23 / 255, green: 23 / 255, blue: 26 / 255)
    static let line = Color(red: 42 / 255, green: 42 / 255, blue: 47 / 255)
    static let field = Color(red: 38 / 255, green: 38 / 255, blue: 43 / 255)
    static let tile = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255)
    static let channel = Color(red: 29 / 255, green: 31 / 255, blue: 38 / 255)
    static let dim = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.55)
    static let soft = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.75)
    static let gold = Color(red: 1, green: 0.79, blue: 0.3)
}

/// Pictures load off the main thread and are kept in memory for the session.
@MainActor
final class MacImages {
    static let shared = MacImages()
    private let cache = NSCache<NSURL, NSImage>()
    private var running: [URL: Task<NSImage?, Never>] = [:]
    func image(_ url: URL) async -> NSImage? {
        if let i = cache.object(forKey: url as NSURL) { return i }
        if let t = running[url] { return await t.value }
        let t = Task.detached(priority: .utility) { () -> NSImage? in
            guard let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return NSImage(data: d)
        }
        running[url] = t
        let i = await t.value
        running[url] = nil
        if let i { cache.setObject(i, forKey: url as NSURL) }
        return i
    }
}

struct MacImage<Placeholder: View>: View {
    let url: URL?
    var fill = true
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else { placeholder() }
        }
        .task(id: url) { image = nil; if let url { image = await MacImages.shared.image(url) } }
    }
}

/// A film or series poster; a thin bar shows how far it was watched (from the resume store).
struct PosterTile: View {
    let item: MediaItem
    var w: CGFloat = 124, h: CGFloat = 186
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: MacNav
    @State private var hover = false
    var body: some View {
        Button { nav.open(item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    MacImage(url: Img.url(item.img)) {
                        ZStack { MacTheme.tile; Text(item.name).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center).padding(8) }
                    }
                    .frame(width: w, height: h).clipped()
                    if let f = progress, f > 0.01 { ProgressLine(fraction: f).padding(8) }
                    if let l = item.lang { Text(l).font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.red)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6) }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(hover ? 0.9 : 0), lineWidth: 2))
                .scaleEffect(hover ? 1.03 : 1)
                Text(item.name).font(.system(size: 12)).foregroundStyle(MacTheme.soft).lineLimit(1).frame(width: w, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .accessibilityIdentifier("tile:" + item.key)
        .accessibilityLabel(item.name)
    }
    /// Films: their own resume point; series: the last episode watched.
    private var progress: Double? {
        if item.kind == .series { return user.lastEpisode(ofSeries: item.id)?.fraction }
        return user.resumePoint(item)?.fraction
    }
}

struct ProgressLine: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: max(4, g.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Watched \(Int(fraction * 100)) percent")
        .accessibilityIdentifier("progress")
    }
}

/// A live channel: its logo on a dark card, the name under it.
struct ChannelTile: View {
    let item: MediaItem
    var w: CGFloat = 150, h: CGFloat = 84
    let play: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: play) {
            VStack(spacing: 6) {
                MacImage(url: Img.url(item.img), fill: false) { EmptyView() }
                    .frame(width: w * 0.6, height: h * 0.46)
                Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
            }
            .frame(width: w, height: h)
            .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.channel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(hover ? 0.9 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityIdentifier("channel:" + item.id)
        .accessibilityLabel(item.name)
    }
}

/// Section title for a row: "Belgium  Live now".
struct RowTitle: View {
    let title: String
    var sub: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .bold))
            if let sub { Text(sub).font(.system(size: 13, weight: .medium)).foregroundStyle(MacTheme.dim) }
        }
        .padding(.bottom, 4)
    }
}

/// A horizontal row of tiles that scrolls sideways.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) { content() }.padding(.vertical, 4)
        }
    }
}

/// Pill buttons of the design: white primary, translucent secondary.
struct MacPill: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16).frame(height: 34)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)))
            .overlay(Capsule().stroke(primary ? Color.white : Color.white.opacity(0.16), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The lockup: the mark and "tv" (the opening's last frame).
struct Wordmark: View {
    var size: CGFloat = 15
    var body: some View {
        Image("Lockup").resizable().interpolation(.high).scaledToFit().frame(height: size * 2.1)
            .accessibilityElement().accessibilityLabel("Nexus TV").accessibilityIdentifier("lockup")
    }
}

/// Loading placeholder.
struct Shimmer: View {
    var body: some View { RoundedRectangle(cornerRadius: 8).fill(MacTheme.tile) }
}
