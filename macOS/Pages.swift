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
    private let rotate = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !user.continueList.isEmpty {
                    VStack(alignment: .leading) {
                        RowTitle(title: "Continue watching")
                        TileRow {
                            ForEach(user.continueList, id: \.item.key) { r in
                                ResumeTile(point: r) { Player(nav: nav).play(r.item, startMs: r.posMs) }
                            }
                        }
                    }
                }
                ForEach(settings.countries, id: \.self) { cc in CountryRow(cc: cc) }
                if !catalog.newFilms.isEmpty {
                    VStack(alignment: .leading) {
                        RowTitle(title: "New films", sub: "Recently added")
                        TileRow { ForEach(catalog.newFilms, id: \.key) { PosterTile(item: $0) } }
                    }
                }
                if !catalog.topSeries.isEmpty {
                    VStack(alignment: .leading) {
                        RowTitle(title: "Top series")
                        TileRow { ForEach(catalog.topSeries, id: \.key) { PosterTile(item: $0) } }
                    }
                }
                if !user.myList.isEmpty {
                    VStack(alignment: .leading) {
                        RowTitle(title: "My List")
                        TileRow { ForEach(user.myList, id: \.key) { PosterTile(item: $0) } }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
        }
        .onReceive(rotate) { _ in if catalog.hero.count > 1 { withAnimation(.easeInOut(duration: 0.6)) { heroIdx = (heroIdx + 1) % catalog.hero.count } } }
    }

    @ViewBuilder private var hero: some View {
        if catalog.hero.isEmpty {
            Shimmer().frame(height: 318)
        } else {
            let h = catalog.hero[heroIdx % catalog.hero.count]
            let series = MediaItem(kind: .series, id: h.id, name: h.title, img: h.cover)
            ZStack(alignment: .bottomLeading) {
                MacImage(url: Img.url(h.backdrop, .backdrop)) { Color.black }
                    .frame(maxWidth: .infinity, maxHeight: 318).clipped()
                    .id(h.id).transition(.opacity)
                LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0), .init(color: .black.opacity(0.55), location: 0.42),
                                       .init(color: .clear, location: 0.75)], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOP SERIES").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(MacTheme.soft)
                    Text(h.title).font(.system(size: 42, weight: .heavy)).tracking(-1).lineLimit(1)
                    Text([h.year, h.genre, h.rating.isEmpty ? "" : "★ " + String(h.rating.prefix(3))].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.system(size: 13)).foregroundStyle(MacTheme.soft)
                    Text(h.plot).font(.system(size: 13.5)).lineSpacing(3).foregroundStyle(MacTheme.soft).lineLimit(2).frame(width: 520, alignment: .leading)
                    HStack(spacing: 10) {
                        Button { nav.open(series) } label: { Label("Watch", systemImage: "play.fill") }.buttonStyle(MacPill(primary: true))
                        Button { user.toggle(series) } label: {
                            user.inList(series) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                        }.buttonStyle(MacPill())
                    }
                    .padding(.top, 8)
                }
                .padding(.leading, 32).padding(.bottom, 30)
                HStack(spacing: 6) {
                    ForEach(0..<catalog.hero.count, id: \.self) { i in
                        Capsule().fill(i == heroIdx % catalog.hero.count ? Color.white : Color.white.opacity(0.4)).frame(width: i == heroIdx % catalog.hero.count ? 22 : 7, height: 7)
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
}

/// A film or episode being watched: its picture, the progress bar, a click resumes playback.
struct ResumeTile: View {
    let point: ResumePoint
    let play: () -> Void
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    MacImage(url: Img.url(point.item.img)) { MacTheme.tile }.frame(width: 124, height: 186).clipped()
                    ProgressLine(fraction: point.fraction).padding(8)
                }
                .frame(width: 124, height: 186).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(point.item.name).font(.system(size: 12)).foregroundStyle(MacTheme.soft).lineLimit(1).frame(width: 124, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resume:" + point.item.key)
    }
}

/// A country's row of live channels on Home.
struct CountryRow: View {
    let cc: String
    @EnvironmentObject var catalog: Catalog
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
                ForEach(Array(items.enumerated()), id: \.element.key) { i, it in
                    ChannelTile(item: it) { Player(nav: nav).play(it, list: items, index: i) }
                }
            }
        }
        .task(id: catalog.state == .ready) { if catalog.state == .ready { items = await catalog.countryRow(cc).items } }
    }
}

// MARK: - Live TV

struct LivePage: View {
    let country: String
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav
    @State private var group: String = ""
    @State private var channels: [MediaItem] = []

    var body: some View {
        if country.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RowTitle(title: "Countries")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(catalog.liveCountries, id: \.0) { c in
                            Button { nav.go(.live(c.0)) } label: {
                                HStack { Text(c.0).font(.system(size: 12, weight: .bold)).frame(width: 36); Text(Countries.name(c.0)); Spacer(); Text("\(c.1) groups").foregroundStyle(MacTheme.dim) }
                                    .padding(.horizontal, 14).frame(height: 44).background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.tile))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
        } else {
            let groups = catalog.liveGroups(country)
            HStack(spacing: 0) {
                List(groups, id: \.id, selection: Binding(get: { group.isEmpty ? groups.first?.id : group }, set: { group = $0 ?? "" })) { g in
                    HStack { Text(Clean.titleCase(Clean.category(g.name))).lineLimit(1).foregroundStyle(Color.white.opacity(0.9)); Spacer()
                        if let n = catalog.liveIndex[g.id]?.count { Text("\(n)").foregroundStyle(MacTheme.dim).monospacedDigit() } }
                    .font(.system(size: 13))
                    .tag(g.id)
                    .accessibilityIdentifier("group:" + g.id)
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden).background(MacTheme.sidebar.opacity(0.6))
                .frame(width: 260)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 14) {
                        ForEach(Array(channels.enumerated()), id: \.element.key) { i, it in
                            ChannelTile(item: it) { Player(nav: nav).play(it, list: channels, index: i) }
                        }
                    }
                    .padding(20)
                }
            }
            .task(id: (group.isEmpty ? groups.first?.id : group) ?? "") {
                guard let g = (group.isEmpty ? groups.first?.id : group) else { channels = []; return }
                let label = Countries.name(country) + " · " + Clean.titleCase(Clean.category(groups.first { $0.id == g }?.name ?? ""))
                channels = await catalog.channels(g).map { MediaItem(kind: .live, id: $0.id, name: $0.name, img: $0.icon, sub: label) }
            }
            .onChange(of: country) { _, _ in group = "" }
        }
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

struct MyListPage: View {
    @EnvironmentObject var user: UserStore
    var body: some View {
        ScrollView {
            if user.myList.isEmpty {
                Text("Titles you add with My List show here.").foregroundStyle(MacTheme.dim).padding(40)
            }
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
                    Text("Type in the search field on the left (⌘F). Channels, films and series of every language.").foregroundStyle(MacTheme.dim)
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
