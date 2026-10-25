import SwiftUI

/// Home: rotating featured series on top, shelves below. Rows follow Settings › Home rows; each country row
/// starts with that country's favourite channels and ends with an "All channels" tile.
struct HomeView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var heroIdx = 0
    @ObservedObject private var chrome = Chrome.shared
    @ObservedObject private var followed = FollowedShows.shared
    @FocusState private var heroButton: Int?
    private let rotate = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    /// Rows that draw something (empty Continue watching / My List rows are left out).
    private var renderedRows: [String] {
        settings.visibleRows.filter { id in
            switch id {
            case "updates": return !updates.isEmpty
            case "continue": return !user.continueList.isEmpty
            case "mylist": return !user.myList.isEmpty
            case "favMore": return !user.favs(outside: settings.countries).isEmpty
            default: return !id.hasPrefix("list:") || settings.lists.contains { $0.key == id }
            }
        }
    }

    /// Followed shows with episodes not seen yet (rule 4).
    private var updates: [NewShow] { followed.visible(followed: user.followedSeries) }
    /// Shows with new episodes first, then the top series (rule 5).
    private var heroes: [HomeHero] { HomeHero.list(updates: updates, base: catalog.hero) }
    private var hero: HomeHero? { let h = heroes; return h.isEmpty ? nil : h[heroIdx % h.count] }

    var body: some View {
        let _ = Metrics.shared.count("HomeView")
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                // lazy: only the rows on screen exist (all of them, with their tiles, was the cost of each focus move)
                LazyVStack(alignment: .leading, spacing: 0) {
                    heroSection
                    ForEach(renderedRows, id: \.self) { row in
                        shelf(row)
                            .environment(\.isFirstRow, row == renderedRows.first)
                            .disabled(nav.movingRow != nil && nav.movingRow != row)
                    }
                    Color.clear.frame(height: 140)
                }
            }

            // solid mask: rows never show under the header area once scrolled
            Color.black.frame(height: 150).opacity(chrome.scrolled ? 1 : 0).allowsHitTesting(false)
        }
        .onReceive(rotate) { _ in
            let n = heroes.count
            guard n > 1, !chrome.headerHidden, nav.playing == nil, nav.movingRow == nil, heroButton == nil else { return }
            withAnimation(.easeInOut(duration: 0.6)) { heroIdx = (heroIdx + 1) % n }
        }
        // rule 3: on Home load, then at most once an hour (the store keeps the time); again when the followed shows or the account change
        .task(id: "\(catalog.state == .ready)-\(catalog.activeId)-\(user.followedSeries.map(\.id).joined(separator: ","))") {
            guard catalog.state == .ready else { return }
            followed.configure(catalog: catalog)
            await followed.refresh(followed: user.followedSeries)
        }
    }

    // MARK: hero

    private func stepHero(_ d: Int) {
        let n = heroes.count
        guard n > 1 else { return }
        withAnimation(.easeOut(duration: 0.25)) { heroIdx = (heroIdx + d + n) % n }
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if let h = hero {
                    RemoteImage(url: Img.url(h.backdrop, .backdrop), maxPixel: 1920, mode: .fill) { Color.black }
                        .frame(width: 1920, height: 760).clipped()
                        .id(h.id).transition(.opacity)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0), .init(color: .black.opacity(0.55), location: 0.38),
                                       .init(color: .black.opacity(0), location: 0.7)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0), location: 0.22),
                                       .init(color: .black.opacity(0), location: 0.62), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: 1920, height: 760)

            if let h = hero {
                VStack(alignment: .leading, spacing: 0) {
                    Text(h.kicker).font(.ui(20, .bold)).tracking(3).textCase(.uppercase).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 14)
                    Text(h.title).font(.ui(76, .bold)).tracking(-1).lineLimit(1).padding(.bottom, 16)
                    Facts(parts: h.facts).padding(.bottom, 16)
                    Text(h.plot).font(.ui(24)).lineSpacing(6).foregroundStyle(.white.opacity(0.72)).lineLimit(2).frame(width: 900, alignment: .leading)
                }
                .frame(width: 900, alignment: .leading)
                .padding(.leading, Theme.x0).padding(.top, 168)
                .onAppear { Metrics.shared.mark("ready:home-hero", once: true) }
                .id("meta" + h.id).transition(.opacity)

                HStack(spacing: 22) {
                    Button { if let n = h.update { playNew(n) } else { nav.open(seriesItem(h)) } } label: { Label(h.update == nil ? "Watch" : "Play", systemImage: "play.fill") }
                        .focused($heroButton, equals: 0)
                    Button { user.toggle(seriesItem(h)) } label: {
                        user.inList(seriesItem(h)) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                    }
                    .focused($heroButton, equals: 1)
                }
                .buttonStyle(PillButtonStyle())
                // Left on Watch / Right on My List switch the featured title
                .onMoveCommand { d in
                    if d == .left && heroButton == 0 { stepHero(-1) }
                    if d == .right && heroButton == 1 { stepHero(1) }
                    // this handler takes the move from the focus engine: Up must be sent to the menu by hand
                    if d == .right && heroButton == 0 { heroButton = 1 }
                    if d == .left && heroButton == 1 { heroButton = 0 }
                    if d == .up { nav.focusMenuTick += 1 }
                }
                .onChange(of: heroButton) { _, f in if f != nil { chrome.headerHidden = false; chrome.scrolled = false } }
                .padding(.leading, Theme.x0)
                .frame(width: 1920, alignment: .leading)   // full-width band: moving down from the menu lands here
                .focusSection()
                .defaultFocus($heroButton, 0, priority: .userInitiated)   // entering the band lands on Watch
                .padding(.top, 494)
                .disabled(nav.movingRow != nil)

                HStack(spacing: 10) {
                    ForEach(0..<heroes.count, id: \.self) { i in
                        Capsule().fill(i == heroIdx % heroes.count ? Color.white : Color.white.opacity(0.35)).frame(width: i == heroIdx % heroes.count ? 34 : 10, height: 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, Theme.x0).padding(.top, 625)
            } else {
                // placeholders straight away, no waiting on an empty screen
                VStack(alignment: .leading, spacing: 22) {
                    Skeleton(radius: 8).frame(width: 200, height: 22)
                    Skeleton(radius: 12).frame(width: 640, height: 76)
                    Skeleton(radius: 8).frame(width: 820, height: 24)
                    Skeleton(radius: 8).frame(width: 700, height: 24)
                }
                .padding(.leading, Theme.x0).padding(.top, 176)
            }
        }
        .frame(width: 1920, height: 600, alignment: .topLeading)
        .zIndex(-1)
    }

    private func seriesItem(_ h: HomeHero) -> MediaItem { MediaItem(kind: .series, id: h.id, name: h.title, img: h.cover) }

    /// The hero's Play on a show with new episodes: the newest new episode, with the ones after it queued.
    private func playNew(_ n: NewShow) {
        Task {
            let snap = await followed.fetch?(n.series)
            let title = Clean.display(n.series.name)
            let poster = n.series.img
            guard let p = EpisodeDiff.plan(episodes: snap?.episodes ?? n.episodes, play: n.newest.id, series: n.series, title: title, poster: poster) else { return }
            nav.play(p.item, startMs: 0, subtitle: p.item.sub, next: p.next, picture: n.backdrop.isEmpty ? poster : n.backdrop)
        }
    }

    // MARK: shelves

    @ViewBuilder
    private func shelf(_ id: String) -> some View {
        switch id {
        case "updates":
            let u = updates
            if !u.isEmpty {
                Shelf(rowId: id, title: "New episodes", sub: nil, shape: .poster,
                      tiles: u.map { ShelfItem(item: $0.series, badge: $0.badge, caption: $0.caption, update: $0) })
            }
        case "continue":
            let c = user.continueList
            if !c.isEmpty {
                Shelf(rowId: id, title: "Continue watching", sub: nil, shape: .poster,
                      tiles: c.map { r in ShelfItem(item: r.item, progress: r.durMs > 0 ? r.fraction : nil, resume: r) })
            }
        case "mylist":
            if !user.myList.isEmpty {
                Shelf(rowId: id, title: "My List", sub: nil, shape: .poster, tiles: user.myList.map { ShelfItem(item: $0) })
            }
        case "favMore":
            let f = user.favs(outside: settings.countries)
            if !f.isEmpty {
                Shelf(rowId: id, title: "More favourites", sub: "Starred in Settings › Channels", shape: .logo, tiles: f.map { ShelfItem(item: $0, fav: true) })
            }
        case "newFilms":
            Shelf(rowId: id, title: "New films", sub: nil, shape: .poster, tiles: catalog.newFilms.map { ShelfItem(item: $0) },
                  loading: catalog.newFilms.isEmpty && catalog.state != .ready)
        case "topSeries":
            Shelf(rowId: id, title: "Top series", sub: nil, shape: .poster, tiles: catalog.topSeries.map { ShelfItem(item: $0) },
                  loading: catalog.topSeries.isEmpty && catalog.state != .ready)
        default:
            if id.hasPrefix("live:") { CountryShelf(cc: String(id.dropFirst(5))) }
            else if let l = settings.lists.first(where: { $0.key == id }) { ListShelf(list: l) }
        }
    }
}

private struct IsFirstRow: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Home: the first row under the hero (the header stays while it has focus).
    var isFirstRow: Bool {
        get { self[IsFirstRow.self] }
        set { self[IsFirstRow.self] = newValue }
    }
}

/// One tile in a shelf: an item, or the "All <country> channels" tile.
struct ShelfItem: Identifiable {
    var item: MediaItem
    var progress: Double? = nil
    var resume: ResumePoint? = nil
    var fav = false
    var allChannels: (cc: String, total: Int?)? = nil
    /// "New episodes" row: "2 new" on the poster, "S2 E5 · Title" under it.
    var badge: String? = nil
    var caption: String? = nil
    var update: NewShow? = nil
    var id: String { allChannels.map { "all:" + $0.cc } ?? item.key }
}

/// A country row: favourites of that country first (gold star), then its everyday channels, then "All channels".
struct CountryShelf: View {
    let cc: String
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @State private var row: (items: [MediaItem], total: Int?) = ([], nil)
    @State private var loaded = false

    var body: some View {
        let _ = Metrics.shared.count("CountryShelf")
        let favs = user.favs(in: cc)
        let favIds = Set(favs.map(\.id))
        let tiles = favs.map { ShelfItem(item: $0, fav: true) }
            + row.items.filter { !favIds.contains($0.id) }.map { ShelfItem(item: $0) }
            + (loaded ? [ShelfItem(item: MediaItem(kind: .live, id: "all-" + cc, name: "All \(Countries.name(cc)) channels"), allChannels: (cc, row.total))] : [])
        Shelf(rowId: "live:" + cc, title: Countries.name(cc), sub: "Live now", shape: .logo, tiles: tiles, loading: !loaded && favs.isEmpty, cc: cc)
            .task(id: "\(catalog.liveCats.count)-\(catalog.liveIndex.count)") {
                guard !catalog.liveCats.isEmpty else { return }
                let r = await catalog.countryRow(cc)
                row = r; loaded = true
                Metrics.shared.mark("ready:home-row", once: true)
            }
    }
}

/// A category the owner added in Settings › Lists.
struct ListShelf: View {
    let list: HomeList
    @EnvironmentObject var catalog: Catalog
    @State private var items: [MediaItem] = []
    @State private var loaded = false
    var body: some View {
        let _ = Metrics.shared.count("ListShelf")
        Shelf(rowId: list.key, title: list.name, sub: list.t == .live ? "Live" : list.t == .film ? "Films" : "Series",
              shape: list.t == .live ? .logo : .poster, tiles: items.prefix(40).map { ShelfItem(item: $0) }, loading: !loaded)
            .task(id: "\(list.key)-\(catalog.activeId)") { items = await catalog.listItems(list); loaded = true }
    }
}

/// A titled horizontal row of tiles. Long press on a tile opens its menu; "Move row" makes the row jiggle.
struct Shelf: View {
    let rowId: String
    let title: String
    let sub: String?
    let shape: TileShape
    let tiles: [ShelfItem]
    var loading = false
    var cc: String? = nil
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var settings: Settings

    var body: some View {
        let _ = Metrics.shared.count("Shelf")
        let w: CGFloat = shape == .logo ? 260 : 200, h: CGFloat = shape == .logo ? 156 : 300
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.ui(26, .semibold)).foregroundStyle(.white.opacity(0.9))
                if let sub { Text(sub).font(.ui(26)).foregroundStyle(.white.opacity(0.45)) }
                if nav.movingRow == rowId {
                    Text("Swipe left or right to move · click to drop").font(.ui(22)).foregroundStyle(Theme.gold)
                }
            }
            .padding(.leading, 114)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 26) {
                    if loading && tiles.isEmpty {
                        SkeletonRow(w: w, h: h, gap: 26, count: shape == .logo ? 7 : 9)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                        ShelfTile(tile: t, shape: shape, rowId: rowId, cc: cc, list: shown.map(\.item).filter { $0.kind == .live && !$0.id.hasPrefix("all-") }, index: i)
                            .disabled(nav.movingTile != nil && nav.movingTile != t.id)
                    }
                }
                .padding(.horizontal, 114)
                .padding(.top, 30)       // room for the focused tile's lift, so it never touches the title
                .padding(.bottom, 8)
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, shape == .logo ? 8 : 40)
        .focusSection()
        // moving one tile: the others are disabled, so left/right land here and slide it; the rest glide aside
        .onMoveCommand { d in
            guard nav.movingRow == rowId, let key = nav.movingTile, d == .left || d == .right else { return }
            let keys = shown.filter { $0.allChannels == nil }.map(\.id)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { settings.moveTile(rowId, key, by: d == .left ? -1 : 1, keys: keys) }
        }
    }

    /// Tiles in the owner's order; the "All channels" tile stays last.
    private var shown: [ShelfItem] {
        let movable = tiles.prefix(40).filter { $0.allChannels == nil }
        return settings.ordered(rowId, Array(movable), key: \.id) + tiles.filter { $0.allChannels != nil }
    }
}

struct ShelfTile: View {
    let tile: ShelfItem
    let shape: TileShape
    let rowId: String
    let cc: String?
    let list: [MediaItem]
    let index: Int
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var settings: Settings
    @Environment(\.isFirstRow) private var isFirstRow
    @FocusState private var focused: Bool

    private var item: MediaItem { tile.item }

    var body: some View {
        let _ = Metrics.shared.count("ShelfTile")
        let w: CGFloat = shape == .logo ? 260 : 200, h: CGFloat = shape == .logo ? 156 : 300
        VStack(spacing: 0) {
            Button(action: activate) {
                if let all = tile.allChannels {
                    VStack(spacing: 8) {
                        Text(item.name).font(.ui(22, .semibold)).multilineTextAlignment(.center).lineLimit(2)
                        Text(all.total.map { "\($0) channels ›" } ?? "Open the guide ›").font(.ui(18)).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 16).frame(width: w, height: h).background(Theme.tile)
                } else {
                    TileFace(item: item, shape: shape, w: w, h: h, progress: tile.progress, fav: tile.fav)
                        .overlay(alignment: .topTrailing) {
                            if let b = tile.badge {
                                Text(b).font(.ui(18, .bold)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.red)).padding(10)
                            }
                        }
                }
            }
            .buttonStyle(TileButtonStyle())
            .scaleEffect(moving ? 1.06 : 1)
            .offset(y: moving ? -6 : 0)
            .modifier(Jiggle(on: moving, seed: index))
            .focused($focused)
            .onChange(of: focused) { _, f in if f, nav.tab == .home, Chrome.shared.headerHidden == isFirstRow { Chrome.shared.headerHidden = !isFirstRow; if isFirstRow { Chrome.shared.scrolled = false } } }
            .tileMenu(for: item, nav: nav, row: rowId, tile: tile.id) { if tile.allChannels == nil { menu } }
            if let cap = tile.caption {
                Text(cap).font(.ui(20, .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).frame(width: w, alignment: .leading).padding(.top, 12)
            }
            if shape == .logo {
                HStack(spacing: 10) {
                    Text(item.name).font(.ui(22, .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    if tile.allChannels == nil { LivePill() }
                }
                .frame(width: 380, height: 36)
                .padding(.top, 16)
                .opacity(focused && nav.movingRow == nil ? 1 : 0)
                .frame(width: w)
            }
        }
    }

    private var moving: Bool { nav.movingTile == tile.id }

    private func activate() {
        if nav.movingRow != nil { nav.stopMoving(); return }
        if let all = tile.allChannels { nav.openGuide(all.cc); return }
        if let r = tile.resume { nav.play(r.item, startMs: r.posMs, subtitle: r.item.seriesName ?? "", picture: r.item.img); return }
        if let u = tile.update { FollowedShows.shared.seasonHint[u.id] = String(u.newest.season); nav.open(item); return }
        if item.kind == .live {
            let i = list.firstIndex { $0.id == item.id } ?? 0
            nav.play(item, list: list, index: i, subtitle: item.sub)
        } else { nav.open(item) }
    }

    @ViewBuilder
    private var menu: some View {
        Button { nav.movingRow = rowId; nav.movingTile = tile.id } label: { Label("Move", systemImage: "arrow.left.arrow.right") }
        if item.kind == .live {
            Button { user.toggleFav(item, cc: cc ?? "") } label: {
                user.isFav(item.id) ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
            }
        }
        if tile.resume == nil {
            Button { user.toggle(item) } label: {
                user.inList(item) ? Label("Remove from My List", systemImage: "minus.circle") : Label("Add to My List", systemImage: "plus")
            }
        }
        if let r = tile.resume {
            Button(role: .destructive) { user.removeResume(r) } label: { Label("Remove from Continue watching", systemImage: "xmark.circle") }
        }
        Button { settings.hideRow(rowId); user.show("Row hidden · Settings › Home rows shows it again") } label: { Label("Hide row", systemImage: "eye.slash") }
    }
}
