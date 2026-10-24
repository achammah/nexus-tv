import SwiftUI

// Apple TV: Films, Series and Live TV as shelves by family (layout 2a) with the 3b banner card, scaled for 1920 x 1080.
// A card opens the whole list (posters, or the guide on that channel list); "See all" opens every card of a family.

private let cardW: CGFloat = 400

/// One family on the TV: its name and count, then a row of cards ending with a "See all" tile.
struct TVShelf<Cards: View>: View {
    let title: String
    let count: String
    var seeAll: (() -> Void)? = nil
    @ViewBuilder var cards: () -> Cards
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.ui(34, .bold))
                Text(count).font(.ui(24)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.leading, Theme.x0)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    cards()
                    if let seeAll {
                        Button(action: seeAll) {
                            VStack(spacing: 8) { Text("See all").font(.ui(26, .semibold)); Text(count).font(.ui(20)).opacity(0.6) }
                                .frame(width: 200, height: cardW * 162 / 288).background(Theme.glass)
                        }
                        .buttonStyle(TileButtonStyle(radius: 17, scale: 1.06, lift: 6))
                        .accessibilityIdentifier("seeall:" + title)
                    }
                }
                .padding(.horizontal, Theme.x0).padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf:" + title)
    }
}

/// Films or Series tab: the page language, then the six families; small lists behind one button at the end.
struct BrowseTVView: View {
    let kind: ItemKind
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: Nav
    @State private var showSmall = false
    @FocusState private var focus: String?
    @State private var last: String?

    var body: some View {
        let lib = Browse.library(kind == .film ? catalog.vodCats : catalog.seriesCats, counts: catalog.counts, language: nav.browseLang)
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    Text("Language").font(.ui(22)).foregroundStyle(.white.opacity(0.5)).padding(.trailing, 6)
                    ForEach([("EN", "English"), ("FR", "Français")], id: \.0) { code, name in
                        Button(name) { nav.browseLang = code }
                            .buttonStyle(ChipButtonStyle(selected: nav.browseLang == code, height: 48, radius: 24, font: 21, hPad: 20, idle: Color.white.opacity(0.07), onFill: Color.white.opacity(0.2)))
                    }
                    Spacer()
                    Text("\(lib.visibleCount) lists" + (lib.hidden.isEmpty ? "" : " · \(lib.hidden.count) small lists hidden")).font(.ui(22)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, Theme.x0)
                .focusSection()
                if lib.shelves.isEmpty { SkeletonRow(w: cardW, h: cardW * 162 / 288, gap: 32, count: 4).padding(.leading, Theme.x0) }
                ForEach(lib.shelves) { shelf in
                    if shelf.key == Browse.Family.services.rawValue {
                        TVShelf(title: shelf.name, count: Browse.count(lib.services.count, "service")) {
                            ForEach(lib.services, id: \.service.name) { s in
                                BannerCard(model: BannerModels.service(s.service, lists: s.lists.count), width: cardW) {
                                    // One list only: open it straight away.
                                    if s.lists.count == 1, let only = s.lists.first { open(only) }
                                    else { nav.browse.append(BrowseRef(kind: kind, key: "svc:" + s.service.name, title: s.service.name)) }
                                }
                                .focused($focus, equals: "svc:" + s.service.name)
                            }
                        }
                    } else {
                        TVShelf(title: shelf.name, count: Browse.count(shelf.lists.count, "list"),
                                seeAll: { nav.browse.append(BrowseRef(kind: kind, key: shelf.key, title: shelf.name)) }) {
                            ForEach(shelf.lists) { l in
                                BannerCard(model: BannerModels.list(l, kind: kind, catalog: catalog), width: cardW) { open(l) }
                                    .focused($focus, equals: l.id)
                            }
                        }
                    }
                }
                if !lib.hidden.isEmpty {
                    Button(showSmall ? "Hide small lists" : "Show \(lib.hidden.count) small lists") { showSmall.toggle() }
                        .buttonStyle(PillButtonStyle()).padding(.leading, Theme.x0).accessibilityIdentifier("small-lists")
                    if showSmall {
                        TVShelf(title: "Small lists", count: Browse.count(lib.hidden.count, "list")) {
                            ForEach(lib.hidden) { l in BannerCard(model: BannerModels.list(l, kind: kind, catalog: catalog), width: cardW) { open(l) } }
                        }
                    }
                }
            }
            .padding(.top, 150).padding(.bottom, 80)
        }
        .frame(width: 1920, height: 1080)
        .onAppear { catalog.needIndex() }
        .onChange(of: focus) { _, f in if let f { last = f } }
        // back from a list: focus returns to the card it was opened from
        .onChange(of: nav.browse.isEmpty) { _, e in if e, let l = last { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = l } } }
    }

    private func open(_ l: Browse.List) { nav.browse.append(BrowseRef(kind: kind, ids: l.ids, title: l.label)) }
}

/// Live TV tab: the chosen countries, then the country's nine families; a card opens the guide on that list.
struct LiveBrowseTVView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var cc = ""
    @State private var showSmall = false
    @FocusState private var focus: String?
    @State private var last: String?

    var body: some View {
        Group {
            if cc.isEmpty {
                LiveLandingTV { code in
                    // One list only: open it straight away instead of a page with one card.
                    let live = Browse.live(catalog.liveGroups(code), counts: catalog.liveCounts)
                    let every = live.shelves.flatMap(\.lists) + live.hidden
                    if every.count == 1, let only = every.first { open(only, code) } else { cc = code }
                }
            } else { countryView }
        }
        .onAppear { if let g = nav.guideCountry { nav.guideCountry = nil; cc = g } }
        .onChange(of: nav.guideCountry) { _, g in if let g { nav.guideCountry = nil; cc = g } }
    }

    @ViewBuilder private var countryView: some View {
        let country = cc
        let live = Browse.live(catalog.liveGroups(country), counts: catalog.liveCounts)
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    ForEach(settings.countries, id: \.self) { c in
                        Button(Countries.name(c)) { cc = c }
                            .buttonStyle(ChipButtonStyle(selected: c == country, height: 48, radius: 24, font: 21, hPad: 20, idle: Color.white.opacity(0.07), onFill: Color.white.opacity(0.2)))
                    }
                    Spacer()
                    Text((live.channels > 0 ? Browse.count(live.channels, "channel") + " · " : "") + "\(live.providerLists) provider lists")
                        .font(.ui(22)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, Theme.x0)
                .focusSection()
                ForEach(live.shelves) { shelf in
                    TVShelf(title: shelf.name, count: Browse.count(shelf.lists.count, "list"),
                            seeAll: { nav.browse.append(BrowseRef(kind: .live, key: shelf.key, title: shelf.name, cc: country)) }) {
                        ForEach(shelf.lists) { l in
                            BannerCard(model: BannerModels.live(l, catalog: catalog), width: cardW) { open(l, country) }.focused($focus, equals: l.id)
                        }
                    }
                }
                if !live.hidden.isEmpty {
                    Button(showSmall ? "Hide small lists" : "Show \(live.hidden.count) small lists") { showSmall.toggle() }
                        .buttonStyle(PillButtonStyle()).padding(.leading, Theme.x0).accessibilityIdentifier("small-lists")
                    if showSmall {
                        TVShelf(title: "Small lists", count: Browse.count(live.hidden.count, "list")) {
                            ForEach(live.hidden) { l in BannerCard(model: BannerModels.live(l, catalog: catalog), width: cardW) { open(l, country) } }
                        }
                    }
                }
            }
            .padding(.top, 150).padding(.bottom, 80)
        }
        .frame(width: 1920, height: 1080)
        .task { await catalog.ensureLiveIndex() }
        .onExitCommand { if nav.browse.isEmpty { cc = "" } }
        .onChange(of: focus) { _, f in if let f { last = f } }
        .onChange(of: nav.browse.isEmpty) { _, e in if e, let l = last { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = l } } }
    }

    private func open(_ l: Browse.List, _ cc: String) { nav.browse.append(BrowseRef(kind: .live, ids: l.ids, title: l.label, cc: cc)) }
}

/// A page opened from a shelf: a whole list (posters, or the guide on a channel list) or a family's cards.
struct BrowseTVPage: View {
    let ref: BrowseRef
    /// This page is the one on screen; when it comes back on top, focus returns to the card it left from.
    var top = true
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: Nav
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @FocusState private var focus: String?
    @State private var last: String?
    /// The poster this list page left from, and the tick that focuses it.
    @State private var lastItem: String?
    @State private var tick = 0

    var body: some View {
        Group {
            if ref.ids.isEmpty { family }
            else if ref.kind == .live { GuideView(start: (ref.cc, ref.ids[0])) }
            else { list }
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .background(Color.black)
        .onChange(of: focus) { _, f in if let f { last = f } }
        .onChange(of: top) { _, t in if t { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { refocus() } } }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refocus() } }
        .onChange(of: items.first?.key) { _, _ in if top, lastItem == nil { refocus() } }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(ref.title).font(.ui(34, .bold))
                if !items.isEmpty { Text(Browse.count(items.count, ref.kind == .film ? "film" : "series")).font(.ui(24)).foregroundStyle(.white.opacity(0.5)) }
            }
            .padding(.leading, Theme.x0).padding(.top, 150)
            if loading && items.isEmpty { SkeletonRow(w: 180, h: 270, gap: 32).padding(.leading, Theme.x0).padding(.top, 30) }
            PosterGrid(items: items, columns: 8, w: 180, h: 270, gx: 32, gy: 26, topInset: 34, focusKey: lastItem ?? items.first?.key, focusTick: tick) {
                lastItem = $0.key; nav.open($0)
            }
                .padding(.leading, Theme.x0 - 14)
        }
        .task(id: ref) {
            var out: [MediaItem] = [], seen = Set<String>()
            for id in ref.ids { for it in await catalog.items(ref.kind, id) where seen.insert(it.key).inserted { out.append(it) } }
            items = out; loading = false
        }
    }

    /// The page sets focus itself (the root prefers the current tab): the card or poster it left from, else the first.
    private func refocus() {
        guard top else { return }
        if ref.ids.isEmpty { focus = last ?? models.first?.0.id }
        else if ref.kind != .live { tick += 1 }
    }

    private var family: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text(ref.title).font(.ui(34, .bold)).padding(.leading, Theme.x0)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardW), spacing: 32), count: 4), alignment: .leading, spacing: 40) {
                    ForEach(models, id: \.0.id) { l, m in
                        BannerCard(model: m, width: cardW) {
                            nav.browse.append(BrowseRef(kind: ref.kind, ids: l.ids, title: m.name == l.label ? l.label : ref.title + " · " + m.name, cc: ref.cc))
                        }
                        .focused($focus, equals: l.id)
                    }
                }
                .padding(.horizontal, Theme.x0)
            }
            .padding(.top, 150).padding(.bottom, 80)
        }
    }

    private var models: [(Browse.List, BannerModel)] {
        if ref.kind == .live {
            let live = Browse.live(catalog.liveGroups(ref.cc), counts: catalog.liveCounts)
            return (live.shelves.first { $0.key == ref.key }?.lists ?? []).map { ($0, BannerModels.live($0, catalog: catalog)) }
        }
        let lib = Browse.library(ref.kind == .film ? catalog.vodCats : catalog.seriesCats, counts: catalog.counts, language: nav.browseLang)
        if ref.key.hasPrefix("svc:"), let s = lib.services.first(where: { "svc:" + $0.service.name == ref.key }) {
            let names = Browse.serviceLabels(s.lists, s.service.name)
            return s.lists.enumerated().map { i, l in (l, BannerModels.sub(l, s.service, kind: ref.kind, catalog: catalog, label: names[i])) }
        }
        return (lib.shelves.first { $0.key == ref.key }?.lists ?? []).map { ($0, BannerModels.list($0, kind: ref.kind, catalog: catalog)) }
    }
}
