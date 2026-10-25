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

/// Mac wrapper over the shared loader (Shared/Core/ImageLoader.swift); kept for BannerCard.
@MainActor
final class MacImages {
    static let shared = MacImages()
    func image(_ url: URL, maxPixel: CGFloat = 700) async -> NSImage? {
        guard let cg = await ImageLoader.shared.image(url, maxPixel: maxPixel) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct MacImage<Placeholder: View>: View {
    let url: URL?
    var fill = true
    var maxPixel: CGFloat? = nil
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: CGImage?
    /// The picture size follows the TMDB size in the address; other pictures are tile sized.
    private var px: CGFloat {
        if let maxPixel { return maxPixel }
        let u = url?.absoluteString ?? ""
        return u.contains("/w1280/") ? 1600 : u.contains("/w780/") ? 900 : 700
    }
    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else { placeholder() }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImageLoader.shared.cached(url, maxPixel: px) { image = c; return }
            image = nil
            image = await ImageLoader.shared.image(url, maxPixel: px)
            // a failed picture is tried again once the loader has forgotten the failure
            if image == nil, (try? await Task.sleep(for: .seconds(62))) != nil { image = await ImageLoader.shared.image(url, maxPixel: px) }
        }
    }
}

/// A film or series poster; a thin bar shows how far it was watched (from the resume store).
struct PosterTile: View {
    let item: MediaItem
    var w: CGFloat = 124, h: CGFloat = 186
    /// The Home row it sits in, when it can be moved there.
    var row: TileRowRef? = nil
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav
    @EnvironmentObject var catalog: Catalog
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
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
            // the right-click menu of a show lists its seasons and episodes: read them while the pointer is on the tile
            if h && item.kind == .series { SeriesGuide.shared.prefetch(item, catalog: catalog) }
        }
        .contextMenu { TileMenu.poster(item, row: row, user: user, settings: settings, nav: nav, catalog: catalog) }
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
            ChannelLogoResolver(name: item.name, icon: item.img, sub: item.sub, maxPixel: 300) { logo in
                switch logo {
                case .none: WordmarkTile(name: item.name, w: w, h: h, radius: 8)
                case .loading, .image:
                    VStack(spacing: 6) {
                        ZStack {
                            if case .image(let cg) = logo { Image(decorative: cg, scale: 1).resizable().aspectRatio(contentMode: .fit) }
                        }
                        .frame(width: w * 0.6, height: h * 0.46)
                        Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
                    }
                }
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
        Image("Lockup").resizable().interpolation(.high).scaledToFit().frame(height: size * 1.05).opacity(0.82)
            .accessibilityElement().accessibilityLabel("Nexus TV").accessibilityIdentifier("lockup")
    }
}

/// Loading placeholder.
struct Shimmer: View {
    var body: some View { RoundedRectangle(cornerRadius: 8).fill(MacTheme.tile) }
}

/// A Home row a tile can move in: its id and the keys in the order shown.
struct TileRowRef { let id: String; let keys: [String] }

/// Right-click menus on tiles: open or play, save or remove, move left or right, hide the row.
@MainActor
enum TileMenu {
    @ViewBuilder static func poster(_ it: MediaItem, row: TileRowRef?, user: UserStore, settings: Settings, nav: MacNav, catalog: Catalog) -> some View {
        if it.kind == .series {
            // a show: where you stopped, the show page, any episode, My List (rule 7)
            SeriesMenu(series: it, user: user, nav: nav, catalog: catalog)
        } else {
            Button { nav.open(it) } label: { Label("Open", systemImage: "info.circle") }
            listButton(it, user: user)
        }
        if let row { Divider(); moves(row.id, it.key, keys: row.keys, settings: settings) }
    }

    @ViewBuilder static func resume(_ r: ResumePoint, row: String, keys: [String], user: UserStore, settings: Settings, nav: MacNav, catalog: Catalog) -> some View {
        if r.item.kind == .episode, let sid = r.item.seriesId {
            SeriesMenu(series: MediaItem(kind: .series, id: sid, name: r.item.seriesName ?? "", img: r.item.img), user: user, nav: nav, catalog: catalog)
        } else {
            Button { Player(nav: nav).play(r.item, startMs: r.posMs) } label: { Label("Resume", systemImage: "play.fill") }
            Button { Player(nav: nav).play(r.item) } label: { Label("Play from the start", systemImage: "backward.end.fill") }
            if r.item.kind != .live { listButton(r.item, user: user) }
        }
        Divider()
        Button(role: .destructive) { user.removeResume(r) } label: { Label("Remove from Continue watching", systemImage: "xmark.circle") }
        moves(row, r.item.key, keys: keys, settings: settings)
    }

    @ViewBuilder static func channel(_ it: MediaItem, cc: String, row: String, keys: [String], user: UserStore, settings: Settings, nav: MacNav, play: @escaping () -> Void) -> some View {
        Button(action: play) { Label("Watch", systemImage: "play.fill") }
        if user.isFav(it.id) {
            Button { user.toggleFav(it, cc: cc) } label: { Label("Remove from favourites", systemImage: "star.slash") }
        } else {
            Button { user.toggleFav(it, cc: cc) } label: { Label("Add to favourites", systemImage: "star") }
        }
        Divider()
        moves(row, it.key, keys: keys, settings: settings)
    }

    @ViewBuilder private static func listButton(_ it: MediaItem, user: UserStore) -> some View {
        if user.inList(it) {
            Button { user.toggle(it) } label: { Label("Remove from My List", systemImage: "minus.circle") }
        } else {
            Button { user.toggle(it) } label: { Label("Add to My List", systemImage: "plus") }
        }
    }

    @ViewBuilder private static func moves(_ row: String, _ key: String, keys: [String], settings: Settings) -> some View {
        let i = keys.firstIndex(of: key) ?? 0
        Button { withAnimation { settings.moveTile(row, key, by: -1, keys: keys) } } label: { Label("Move left", systemImage: "arrow.left") }.disabled(i == 0)
        Button { withAnimation { settings.moveTile(row, key, by: 1, keys: keys) } } label: { Label("Move right", systemImage: "arrow.right") }.disabled(i >= keys.count - 1)
        Divider()
        Button { withAnimation { settings.moveRow(row, by: -1) } } label: { Label("Move row up", systemImage: "arrow.up") }
        Button { withAnimation { settings.moveRow(row, by: 1) } } label: { Label("Move row down", systemImage: "arrow.down") }
        Button(role: .destructive) { withAnimation { settings.hideRow(row) } } label: { Label("Hide this row", systemImage: "eye.slash") }
    }
}

// MARK: - Right-click on a show (rule 7)

/// The seasons and episodes of the shows the pointer visited, so a right-click menu can list them.
@MainActor
final class SeriesGuide: ObservableObject {
    static let shared = SeriesGuide()
    @Published private(set) var details: [String: Details] = [:]
    private var loading: Set<String> = []
    func prefetch(_ series: MediaItem, catalog: Catalog) {
        guard details[series.id] == nil, loading.insert(series.id).inserted else { return }
        Task {
            if let d = await catalog.details(MediaItem(kind: .series, id: series.id, name: series.name)) { details[series.id] = d }
            loading.remove(series.id)
        }
    }
}

/// "Show · S1 E3 at 10:34", then Resume E3 · Open the show · Go to episode… (seasons, then episodes) · My List.
struct SeriesMenu: View {
    let series: MediaItem
    let user: UserStore
    let nav: MacNav
    let catalog: Catalog
    @ObservedObject private var guide = SeriesGuide.shared

    var body: some View {
        let last = user.lastEpisode(ofSeries: series.id)
        let d = guide.details[series.id]
        let title = Clean.display(series.name.isEmpty ? (d?.name ?? "") : series.name)
        if let last, let se = PlayerFormat.seasonEpisode(last.item.name) {
            Text("\(title) · S\(se.season) E\(se.episode)" + (last.posMs > 0 ? " at " + PlayerFormat.clock(last.posMs / 1000) : ""))
            Button { play(last.item, at: last.posMs, d: d) } label: { Label("Resume " + (se.season == "1" ? "E\(se.episode)" : "S\(se.season) E\(se.episode)"), systemImage: "play.fill") }
        } else {
            Text(title)
        }
        Button { nav.open(series) } label: { Label("Open the show", systemImage: "info.circle") }
        if let d, !d.seasons.isEmpty {
            Menu {
                ForEach(d.seasons, id: \.self) { s in
                    Menu("Season \(s)") {
                        ForEach(d.episodes[s] ?? [], id: \.id) { e in
                            Button("E\(e.num) · " + (e.title.isEmpty ? "Episode \(e.num)" : e.title)) { play(episodeItem(e, s, d, title), at: user.resumePoint(episodeItem(e, s, d, title))?.posMs ?? 0, d: d) }
                        }
                    }
                }
            } label: { Label("Go to episode…", systemImage: "list.bullet") }
        } else {
            Button { SeriesGuide.shared.prefetch(series, catalog: catalog) } label: { Label("Go to episode… (loading)", systemImage: "list.bullet") }
        }
        if user.inList(series) {
            Button { user.toggle(series) } label: { Label("Remove from My List", systemImage: "minus.circle") }
        } else {
            Button { user.toggle(series) } label: { Label("Add to My List", systemImage: "plus") }
        }
    }

    private func episodeItem(_ e: Episode, _ s: String, _ d: Details, _ title: String) -> MediaItem {
        MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s) E\(e.num)", img: e.still.isEmpty ? d.poster : e.still, ext: e.ext, sub: e.title,
                  seriesId: series.id, seriesName: title)
    }
    /// Plays an episode; the ones after it follow (the player finds them itself when the show is not loaded yet).
    private func play(_ it: MediaItem, at ms: Int, d: Details?) {
        var next: [MediaItem] = []
        if let d {
            let title = Clean.display(series.name.isEmpty ? d.name : series.name)
            let all = d.seasons.flatMap { s in (d.episodes[s] ?? []).map { episodeItem($0, s, d, title) } }
            if let i = all.firstIndex(where: { $0.id == it.id }) { next = Array(all.dropFirst(i + 1)) }
        }
        Player(nav: nav).play(it, startMs: ms, next: next, picture: d?.poster ?? "")
    }
}
