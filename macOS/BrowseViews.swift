import SwiftUI
import AppKit

// Films, Series and a country's Live TV as shelves by family (layout 2a), each list drawn as a cinematic banner
// card (3b): the list's own art full-bleed behind a colour wash from the left, the clean name large inside.

// MARK: - shelves

/// One family: its name, how many lists, "See all N ›", then a sideways row of cards.
struct ShelfSection<Cards: View>: View {
    let title: String
    let count: Int
    let unit: String
    let seeAll: (() -> Void)?
    @ViewBuilder var cards: () -> Cards
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 22, weight: .heavy)).tracking(-0.4)
                Text(unit == "series" ? "\(count) series" : Browse.count(count, String(unit.dropLast()))).font(.system(size: 13)).foregroundStyle(MacTheme.dim)
                Spacer()
                if let seeAll {
                    Button("See all \(count) ›", action: seeAll).buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(MacTheme.soft)
                        .accessibilityIdentifier("seeall:" + title)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) { cards() }.padding(.vertical, 4).padding(.horizontal, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf:" + title)
    }
}

/// Films or Series: the six families as shelves, small lists behind one button at the end.
struct BrowsePage: View {
    let kind: ItemKind
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: MacNav
    @State private var showSmall = false

    var body: some View {
        let lib = Browse.library(kind == .film ? catalog.vodCats : catalog.seriesCats, counts: catalog.counts, language: nav.browseLang)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if lib.shelves.isEmpty { ForEach(0..<3, id: \.self) { _ in Shimmer().frame(height: 200) } }
                ForEach(lib.shelves) { shelf in
                    if shelf.key == Browse.Family.services.rawValue {
                        ShelfSection(title: shelf.name, count: lib.services.count, unit: "services", seeAll: nil) {
                            ForEach(lib.services, id: \.service.name) { s in
                                BannerCard(model: BannerModels.service(s.service, lists: s.lists.count)) {
                                    nav.go(.family(BrowseRef(kind: kind, key: "svc:" + s.service.name, title: s.service.name)))
                                }
                            }
                        }
                    } else {
                        ShelfSection(title: shelf.name, count: shelf.lists.count, unit: "lists",
                                     seeAll: { nav.go(.family(BrowseRef(kind: kind, key: shelf.key, title: shelf.name))) }) {
                            ForEach(shelf.lists) { l in
                                BannerCard(model: BannerModels.list(l, kind: kind, catalog: catalog)) { open(l) }
                            }
                        }
                    }
                }
                if !lib.hidden.isEmpty {
                    Button(showSmall ? "Hide small lists" : "Show \(lib.hidden.count) small lists") { showSmall.toggle() }
                        .buttonStyle(MacPill()).accessibilityIdentifier("small-lists")
                    if showSmall {
                        ShelfSection(title: "Small lists", count: lib.hidden.count, unit: "lists", seeAll: nil) {
                            ForEach(lib.hidden) { l in BannerCard(model: BannerModels.list(l, kind: kind, catalog: catalog)) { open(l) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
        }
        .onAppear { catalog.needIndex() }
    }

    private func open(_ l: Browse.List) { nav.go(.list(BrowseRef(kind: kind, ids: l.ids, title: l.label))) }
}

/// One country's Live TV: nine families, events and pay-per-view last and dimmed.
struct LiveBrowsePage: View {
    let country: String
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: MacNav
    @State private var showSmall = false

    var body: some View {
        let live = Browse.live(catalog.liveGroups(country), counts: catalog.liveCounts)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(live.shelves) { shelf in
                    ShelfSection(title: shelf.name, count: shelf.lists.count, unit: "lists",
                                 seeAll: { nav.go(.family(BrowseRef(kind: .live, key: shelf.key, title: shelf.name, cc: country))) }) {
                        ForEach(shelf.lists) { l in BannerCard(model: BannerModels.live(l, catalog: catalog)) { open(l) } }
                    }
                }
                if !live.hidden.isEmpty {
                    Button(showSmall ? "Hide small lists" : "Show \(live.hidden.count) small lists") { showSmall.toggle() }
                        .buttonStyle(MacPill()).accessibilityIdentifier("small-lists")
                    if showSmall {
                        ShelfSection(title: "Small lists", count: live.hidden.count, unit: "lists", seeAll: nil) {
                            ForEach(live.hidden) { l in BannerCard(model: BannerModels.live(l, catalog: catalog)) { open(l) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
        }
        .task { await catalog.ensureLiveIndex() }
    }

    private func open(_ l: Browse.List) { nav.go(.list(BrowseRef(kind: .live, ids: l.ids, title: l.label, cc: country))) }
}

/// "See all": every card of one family, or the lists inside one service (each with the service badge).
struct BrowseFamilyPage: View {
    let ref: BrowseRef
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: MacNav

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 288, maximum: 288), spacing: 18)], alignment: .leading, spacing: 18) {
                ForEach(models, id: \.0.id) { l, m in
                    BannerCard(model: m) { nav.go(.list(BrowseRef(kind: ref.kind, ids: l.ids, title: m.name == l.label ? l.label : ref.title + " · " + m.name, cc: ref.cc))) }
                }
            }
            .padding(24)
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

/// A whole list: every poster, or every channel (a click plays it, Up/Down in the player zaps through the list).
struct BrowseListPage: View {
    let ref: BrowseRef
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: MacNav
    @State private var items: [MediaItem] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading && items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 16)], spacing: 18) { ForEach(0..<18, id: \.self) { _ in Shimmer().frame(width: 124, height: 186) } }.padding(24)
            }
            if ref.kind == .live {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.key) { i, it in ChannelTile(item: it) { Player(nav: nav).play(it, list: items, index: i) } }
                }
                .padding(24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 16)], alignment: .leading, spacing: 18) {
                    ForEach(items, id: \.key) { PosterTile(item: $0) }
                }
                .padding(24)
            }
        }
        .task(id: ref) {
            loading = true
            var out: [MediaItem] = [], seen = Set<String>()
            for id in ref.ids {
                let part: [MediaItem] = ref.kind == .live
                    ? await catalog.channels(id).map { MediaItem(kind: .live, id: $0.id, name: $0.name, img: $0.icon, sub: Countries.name(ref.cc) + " · " + ref.title) }
                    : await catalog.items(ref.kind, id)
                for it in part where seen.insert(it.key).inserted { out.append(it) }
            }
            items = out
            loading = false
        }
    }
}

// MARK: - toolbar parts

/// The line next to the page title: "55 lists in English · 2 small lists hidden", "8,667 channels · 67 provider lists".
struct BrowseCrumb: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var nav: MacNav
    var body: some View {
        if let t = text { Text(t).font(.system(size: 13)).foregroundStyle(MacTheme.dim).monospacedDigit().lineLimit(1) }
    }
    private var text: String? {
        switch nav.page {
        case .films, .series:
            let lib = Browse.library(nav.page == .films ? catalog.vodCats : catalog.seriesCats, counts: catalog.counts, language: nav.browseLang)
            guard lib.visibleCount > 0 else { return nil }
            return "\(lib.visibleCount) lists in \(nav.browseLang == "FR" ? "Français" : "English")" + (lib.hidden.isEmpty ? "" : " · \(lib.hidden.count) small lists hidden")
        case .live(let cc) where !cc.isEmpty:
            let live = Browse.live(catalog.liveGroups(cc), counts: catalog.liveCounts)
            return (live.channels > 0 ? Browse.count(live.channels, "channel") + " · " : "") + "\(live.providerLists) provider lists"
        default: return nil
        }
    }
}

/// The page-level language of Films and Series (the list names no longer carry " · EN").
struct LanguageMenu: View {
    @EnvironmentObject var nav: MacNav
    var body: some View {
        HStack(spacing: 4) {
            Text("Language").foregroundStyle(MacTheme.dim)
            Menu(nav.browseLang == "FR" ? "Français" : "English") {
                Button("English") { nav.browseLang = "EN" }
                Button("Français") { nav.browseLang = "FR" }
            }
            .menuStyle(.borderlessButton).fixedSize().fontWeight(.semibold)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.field))
        .accessibilityIdentifier("language-menu")
    }
}
