import SwiftUI

/// Plays an item inside the library window (the page it came from stays underneath).
@MainActor
struct Player {
    let nav: MacNav
    func play(_ it: MediaItem, startMs: Int = 0, list: [MediaItem] = [], index: Int = 0, next: [MediaItem] = [], picture: String = "") {
        nav.play(MacPlay(item: it, startMs: startMs, list: list, index: index, next: next, picture: picture.isEmpty ? it.img : picture))
    }
}

// MARK: - Home

struct HomePage: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: MacNav
    @State private var heroIdx = 0
    @ObservedObject private var followed = FollowedShows.shared
    private let rotate = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    /// Followed shows with episodes not seen yet (rule 4), and the hero list that puts them first (rule 5).
    private var updates: [NewShow] { followed.visible(followed: user.followedSeries) }
    private var heroes: [HomeHero] { HomeHero.list(updates: updates, base: catalog.hero) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                // Rows in the owner's order; a right-click on a tile moves it, removes it or hides its row.
                ForEach(settings.visibleRows, id: \.self) { id in row(id) }
                if settings.homeRows.contains(where: { !$0.visible && (HomeRow.mac.contains($0.id) || $0.id.hasPrefix("live:")) }) {
                    Button("Show hidden rows") { settings.showAllRows() }.buttonStyle(MacPill()).accessibilityIdentifier("show-hidden-rows")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
        }
        .onReceive(rotate) { _ in let n = heroes.count; if n > 1 { withAnimation(.easeInOut(duration: 0.6)) { heroIdx = (heroIdx + 1) % n } } }
        // rule 3: on Home load, then at most once an hour (the store keeps the time); again when the followed shows or the account change
        .task(id: "\(catalog.state == .ready)-\(catalog.activeId)-\(user.followedSeries.map(\.id).joined(separator: ","))") {
            guard catalog.state == .ready else { return }
            followed.configure(catalog: catalog)
            await followed.refresh(followed: user.followedSeries)
        }
    }

    /// The hero's Play on a show with new episodes: the newest new episode, with the ones after it queued.
    private func playNew(_ n: NewShow) {
        Task {
            let snap = await followed.fetch?(n.series)
            let title = Clean.display(n.series.name)
            guard let p = EpisodeDiff.plan(episodes: snap?.episodes ?? n.episodes, play: n.newest.id, series: n.series, title: title, poster: n.series.img) else { return }
            Player(nav: nav).play(p.item, next: p.next, picture: n.series.img)
        }
    }

    @ViewBuilder private var hero: some View {
        let all = heroes
        if all.isEmpty {
            Shimmer().frame(height: 318)
        } else {
            let h = all[heroIdx % all.count]
            let series = MediaItem(kind: .series, id: h.id, name: h.title, img: h.cover)
            ZStack(alignment: .bottomLeading) {
                MacImage(url: Img.url(h.backdrop, .backdrop)) { Color.black }
                    .frame(maxWidth: .infinity, maxHeight: 318).clipped()
                    .id(h.id).transition(.opacity)
                LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0), .init(color: .black.opacity(0.55), location: 0.42),
                                       .init(color: .clear, location: 0.75)], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    Text(h.update == nil ? "TOP SERIES" : h.kicker).font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(MacTheme.soft)
                    Text(h.title).font(.system(size: 42, weight: .heavy)).tracking(-1).lineLimit(1)
                    Text(h.facts.joined(separator: "  ·  "))
                        .font(.system(size: 13)).foregroundStyle(MacTheme.soft)
                    Text(h.plot).font(.system(size: 13.5)).lineSpacing(3).foregroundStyle(MacTheme.soft).lineLimit(2).frame(width: 520, alignment: .leading)
                    HStack(spacing: 10) {
                        Button { if let n = h.update { playNew(n) } else { nav.open(series) } } label: { Label(h.update == nil ? "Watch" : "Play", systemImage: "play.fill") }
                            .buttonStyle(MacPill(primary: true)).accessibilityIdentifier("hero-play")
                        Button { user.toggle(series) } label: {
                            user.inList(series) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                        }.buttonStyle(MacPill())
                    }
                    .padding(.top, 8)
                }
                .padding(.leading, 32).padding(.bottom, 30)
                HStack(spacing: 6) {
                    ForEach(0..<all.count, id: \.self) { i in
                        Capsule().fill(i == heroIdx % all.count ? Color.white : Color.white.opacity(0.4)).frame(width: i == heroIdx % all.count ? 22 : 7, height: 7)
                            .onTapGesture { withAnimation { heroIdx = i } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 26).padding(.bottom, 26)
            }
            .frame(height: 318)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("hero")
        }
    }

    @ViewBuilder private func row(_ id: String) -> some View {
        switch id {
        case "updates" where !updates.isEmpty:
            let list = settings.ordered("updates", updates, key: { $0.series.key })
            VStack(alignment: .leading) {
                RowTitle(title: "New episodes")
                TileRow {
                    ForEach(list, id: \.id) { n in
                        PosterTile(item: n.series, row: TileRowRef(id: id, keys: list.map(\.series.key)), update: n)
                    }
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("row:updates")
        case "continue" where !user.continueList.isEmpty:
            let list = settings.ordered("continue", user.continueList, key: { $0.item.key })
            VStack(alignment: .leading) {
                RowTitle(title: "Continue watching")
                TileRow {
                    ForEach(list, id: \.item.key) { r in
                        ResumeTile(point: r) { Player(nav: nav).play(r.item, startMs: r.posMs) }
                            .onHover { h in
                                if h, r.item.kind == .episode, let sid = r.item.seriesId {
                                    SeriesGuide.shared.prefetch(MediaItem(kind: .series, id: sid, name: r.item.seriesName ?? ""), catalog: catalog)
                                }
                            }
                            .contextMenu { TileMenu.resume(r, row: "continue", keys: list.map(\.item.key), user: user, settings: settings, nav: nav, catalog: catalog) }
                    }
                }
            }
        case "newFilms" where !catalog.newFilms.isEmpty:
            posterRow(id, "New films", "Recently added", catalog.newFilms)
        case "topSeries" where !catalog.topSeries.isEmpty:
            posterRow(id, "Top series", nil, catalog.topSeries)
        case "mylist" where !user.myList.isEmpty:
            posterRow(id, "My List", nil, user.myList)
        default:
            if id.hasPrefix("live:") { CountryRow(cc: String(id.dropFirst(5))) }
        }
    }

    private func posterRow(_ id: String, _ title: String, _ sub: String?, _ items: [MediaItem]) -> some View {
        let list = settings.ordered(id, items, key: { $0.key })
        return VStack(alignment: .leading) {
            RowTitle(title: title, sub: sub)
            TileRow {
                ForEach(list, id: \.key) { it in
                    PosterTile(item: it, row: TileRowRef(id: id, keys: list.map(\.key)))
                }
            }
        }
    }
}

/// A film or episode being watched: its picture, the progress bar, a click resumes playback.
struct ResumeTile: View {
    let point: ResumePoint
    let play: () -> Void
    @EnvironmentObject var catalog: Catalog
    /// A poster read from the provider when the saved entry has none (films started from a page without art).
    @State private var fetched = ""
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    MacImage(url: Img.url(point.item.img.isEmpty ? fetched : point.item.img)) { MacTheme.tile }.frame(width: 124, height: 186).clipped()
                    ProgressLine(fraction: point.fraction).padding(8)
                }
                .frame(width: 124, height: 186).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(point.item.name).font(.system(size: 12)).foregroundStyle(MacTheme.soft).lineLimit(1).frame(width: 124, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resume:" + point.item.key)
        .task(id: point.item.key) {
            guard point.item.img.isEmpty, point.item.kind == .film || point.item.kind == .series, fetched.isEmpty else { return }
            if let d = await catalog.details(point.item), !d.poster.isEmpty { fetched = d.poster }
        }
    }
}

/// A country's row of live channels on Home.
struct CountryRow: View {
    let cc: String
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: MacNav
    @State private var items: [MediaItem] = []
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                RowTitle(title: Countries.name(cc), sub: "Live now")
                Spacer()
                Button("All channels") { nav.go(.live(cc)) }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(MacTheme.dim)
            }
            TileRow {
                if items.isEmpty { ForEach(0..<8, id: \.self) { _ in Shimmer().frame(width: 150, height: 84) } }
                let shown = settings.ordered("live:" + cc, items, key: { $0.key })
                ForEach(Array(shown.enumerated()), id: \.element.key) { i, it in
                    ChannelTile(item: it) { Player(nav: nav).play(it, list: shown, index: i) }
                        .contextMenu { TileMenu.channel(it, cc: cc, row: "live:" + cc, keys: shown.map(\.key), user: user, settings: settings, nav: nav, play: { Player(nav: nav).play(it, list: shown, index: i) }) }
                }
            }
        }
        .task(id: catalog.state == .ready) { if catalog.state == .ready { items = await catalog.countryRow(cc).items } }
    }
}

// MARK: - Films and Series

struct LibraryPage: View {
    let kind: ItemKind
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @State private var cat = ""
    @State private var items: [MediaItem] = []
    @State private var loading = false

    var body: some View {
        let cats = catalog.libraryCategories(kind, languages: settings.languages)
        let current = cat.isEmpty ? (cats.first?.id ?? "") : cat
        HStack(spacing: 0) {
            List(cats, id: \.id, selection: Binding(get: { current }, set: { cat = $0 ?? "" })) { c in
                HStack { Text(Clean.titleCase(Clean.category(c.name)) + (Clean.tag(c.name).map { $0.isEmpty ? "" : " · " + $0 } ?? "")).lineLimit(1).foregroundStyle(Color.white.opacity(0.9)); Spacer()
                    if let n = catalog.counts[c.id] { Text("\(n)").foregroundStyle(MacTheme.dim).monospacedDigit() } }
                .tag(c.id)
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden).background(MacTheme.sidebar.opacity(0.6))
            .frame(width: 260)
            ScrollView {
                if loading && items.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 16)], spacing: 18) { ForEach(0..<18, id: \.self) { _ in Shimmer().frame(width: 124, height: 186) } }.padding(20)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 16)], alignment: .leading, spacing: 18) {
                    ForEach(items, id: \.key) { PosterTile(item: $0) }
                }
                .padding(20)
            }
        }
        .onAppear { catalog.needIndex() }
        .task(id: current) {
            guard !current.isEmpty else { return }
            loading = true; items = []
            let list = await catalog.items(kind, current)
            if current == (cat.isEmpty ? (catalog.libraryCategories(kind, languages: settings.languages).first?.id ?? "") : cat) { items = list }
            loading = false
        }
    }
}

/// My List before anything is saved: the same calm, centred style as the empty search.
struct MyListEmptyState: View {
    @EnvironmentObject var nav: MacNav
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.83, green: 0.58, blue: 0.90).opacity(0.22), Color(red: 0.68, green: 0.86, blue: 0.56).opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 104, height: 104)
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1).frame(width: 104, height: 104)
                Image(systemName: "bookmark").font(.system(size: 40, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
            VStack(spacing: 8) {
                Text("Your list is empty").font(.system(size: 26, weight: .bold))
                Text("Save films and series to watch them later.").font(.system(size: 14)).foregroundStyle(MacTheme.dim)
            }
            HStack(spacing: 6) {
                Text("Right-click a poster, then choose").foregroundStyle(MacTheme.dim)
                Label("Add to My List", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.10)))
            }.font(.system(size: 12.5))
            HStack(spacing: 10) {
                Button { nav.go(.films) } label: { Label("Browse films", systemImage: "film") }.buttonStyle(MacPill()).accessibilityIdentifier("mylist-empty:films")
                Button { nav.go(.series) } label: { Label("Browse series", systemImage: "rectangle.stack") }.buttonStyle(MacPill()).accessibilityIdentifier("mylist-empty:series")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 560)
        .accessibilityIdentifier("mylist-empty")
    }
}

struct MyListPage: View {
    @EnvironmentObject var user: UserStore
    var body: some View {
        ScrollView {
            if user.myList.isEmpty { MyListEmptyState() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 16)], alignment: .leading, spacing: 18) {
                ForEach(user.myList, id: \.key) { PosterTile(item: $0) }
            }
            .padding(24)
        }
    }
}

// MARK: - Search

/// Search across everything: channels, films and series of the chosen countries and languages and the added lists,
/// then every other country and language with a badge. The same matching as the Apple TV app.
/// Search before anything is typed: one calm, centred invitation instead of a line of instructions.
struct SearchEmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.83, green: 0.58, blue: 0.90).opacity(0.22), Color(red: 0.68, green: 0.86, blue: 0.56).opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 104, height: 104)
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1).frame(width: 104, height: 104)
                Image(systemName: "magnifyingglass").font(.system(size: 40, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
            VStack(spacing: 8) {
                Text("Search your library").font(.system(size: 26, weight: .bold))
                Text("Live, films and series, in every language.").font(.system(size: 14)).foregroundStyle(MacTheme.dim)
            }
            HStack(spacing: 10) {
                ForEach([("dot.radiowaves.left.and.right", "Live"), ("film", "Films"), ("rectangle.stack", "Series")], id: \.1) { icon, label in
                    Label(label, systemImage: icon).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            HStack(spacing: 6) {
                Text("Press").foregroundStyle(MacTheme.dim)
                Text("⌘F").font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.10)))
                Text("to start typing").foregroundStyle(MacTheme.dim)
            }.font(.system(size: 12.5))
        }
        .frame(maxWidth: .infinity, minHeight: 560)
    }
}

struct SearchPage: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav
    @State private var results: [[MediaItem]] = Array(repeating: [], count: 6)
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    private static let titles = ["Channels", "Films", "Series", "Channels · other countries", "Films · other languages", "Series · other languages"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if nav.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchEmptyState()
                } else if results.allSatisfy(\.isEmpty) {
                    Text(busy || catalog.indexState == .loading ? "Searching the whole catalogue…" : "Nothing found for “\(nav.query)”").foregroundStyle(MacTheme.dim)
                }
                ForEach(0..<6, id: \.self) { i in
                    if !results[i].isEmpty {
                        VStack(alignment: .leading) {
                            RowTitle(title: Self.titles[i], sub: "\(results[i].count)")
                            TileRow {
                                ForEach(Array(results[i].enumerated()), id: \.element.key) { j, it in
                                    if it.kind == .live {
                                        ChannelTile(item: it) { Player(nav: nav).play(it, list: results[i], index: j) }
                                            .overlay(alignment: .topLeading) { badge(it.lang) }
                                    } else { PosterTile(item: it) }
                                }
                            }
                        }
                        .accessibilityElement(children: .contain).accessibilityIdentifier("results:" + Self.titles[i])
                    }
                }
            }
            .padding(24)
        }
        .onAppear { catalog.needIndex(); run() }
        .onChange(of: nav.query) { _, _ in run() }
        .onChange(of: catalog.indexState) { _, s in if s == .ready { run() } }
    }

    @ViewBuilder private func badge(_ l: String?) -> some View {
        if let l { Text(l).font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 3).fill(Color.red)).padding(6) }
    }

    private func run() {
        task?.cancel()
        let needle = nav.query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { results = Array(repeating: [], count: 6); return }
        let chosen = settings.countries
        let groups: [(String, [XCategory])] = chosen.map { ($0, catalog.liveGroups($0)) }
        let films = catalog.index.films, series = catalog.index.series, lists = settings.lists
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            busy = true
            var extra: [MediaItem] = []
            for l in lists { extra += await catalog.listItems(l) }
            let main = await SearchEngine.match(needle, groups: groups, live: catalog.liveIndex, films: films, series: series, extra: extra, other: [], otherLive: [:], maxHits: 40)
            if Task.isCancelled { return }
            results = main
            guard needle.count >= 3 else { busy = false; return }
            await catalog.ensureLiveIndex()
            let other = await catalog.moreIndex()
            if Task.isCancelled { return }
            let otherLive = catalog.liveCodes().filter { !chosen.contains($0.value) }
            results = await SearchEngine.match(needle, groups: groups, live: catalog.liveIndex, films: films, series: series, extra: extra, other: other, otherLive: otherLive, maxHits: 40)
            busy = false
        }
    }
}
