import SwiftUI

/// Settings, laid out like the Mac Settings page: Live countries, Film and series languages, Online subtitles (OpenSubtitles),
/// then Sources (Mac: Settings › Sources). Apple TV only settings sit in the closest Mac section:
/// Channels and Home rows and Lists under Live countries, Menu tabs and the catalogue refresh under Film and series languages,
/// Clear lists under Sources.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case countries = "Live countries", languages = "Film and series languages", subtitles = "Online subtitles (OpenSubtitles)", accounts = "Sources"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .countries: "globe.europe.africa"; case .languages: "character.bubble"; case .subtitles: "captions.bubble"; case .accounts: "link.circle"
            }
        }
    }
    @EnvironmentObject var catalog: Catalog
    @State private var section: Section = .countries
    @State private var overlay: Overlay? = nil
    @FocusState private var side: Section?
    @State private var returnTo: Section = .countries
    enum Overlay { case addList, channels, osub }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Settings").padding(.leading, 32).padding(.top, 30).padding(.bottom, 16)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Section.allCases) { s in
                            Button { section = s } label: {
                                HStack(spacing: 16) { Image(systemName: s.icon).frame(width: 30); Text(s.rawValue) }.frame(width: 328, alignment: .leading)
                            }
                            .buttonStyle(ChipButtonStyle(selected: s == section))
                            .focused($side, equals: s)
                        }
                    }
                    .padding(.horizontal, 18)
                    Spacer()
                }
                .frame(width: 400, height: 840).background(Glass())
                .focusSection()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 44) {
                        switch section {
                        case .countries:
                            CountriesPane()
                            ChannelsPane(browse: { overlay = .channels })
                            OrderPane(kind: .rows)
                            ListsPane(add: { overlay = .addList })
                        case .languages:
                            LanguagesPane()
                            OrderPane(kind: .tabs)
                            CataloguePane()
                        case .subtitles: SubtitlesPane(edit: { overlay = .osub })
                        case .accounts:
                            AccountsPane(add: { catalog.addingSource = true })
                            ClearPane()
                        }
                    }
                    .padding(40)
                    .frame(width: 1276, alignment: .topLeading)
                }
                .frame(width: 1276, height: 840).background(Glass())
                .focusSection()
            }
            .padding(.leading, 112).padding(.top, 150)
            .disabled(overlay != nil)

            if let o = overlay {
                Color.black.ignoresSafeArea()      // opaque: nothing of the Settings screen shows behind a picker
                Group {
                    switch o {
                    case .addList: ListPicker(close: { overlay = nil })
                    case .channels: ChannelPicker(close: { overlay = nil })
                    case .osub: OSubForm(close: { overlay = nil })
                    }
                }
                .onExitCommand { overlay = nil }
            }
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .onChange(of: side) { _, s in if let s { section = s } }
        // closing a picker comes back to the section it was opened from
        .onChange(of: overlay) { _, o in
            if o != nil { returnTo = section; return }
            section = returnTo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { section = returnTo; side = returnTo }
        }
    }
}

struct PaneTitle: View {
    let title: String, note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.ui(36, .bold))
            Text(note).font(.ui(22)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.bottom, 26)
    }
}

/// A block inside a section: a smaller title than the section name, for settings the Mac does not have.
struct BlockTitle: View {
    let title: String, note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.ui(30, .semibold))
            Text(note).font(.ui(20)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.bottom, 14)
    }
}

// MARK: - Menu tabs and Home rows: click shows/hides; "Edit order" (or long press) moves them

private struct OrderPane: View {
    enum Kind { case tabs, rows }
    let kind: Kind
    @EnvironmentObject var settings: Settings
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlockTitle(title: kind == .tabs ? "Menu tabs" : "Home rows",
                      note: editing ? "Use the arrows to move. Done finishes." :
                        (kind == .tabs ? "Click shows or hides a tab. Settings always stays at the end." : "Click shows or hides a row. Lists you add appear here too."))
            HStack(spacing: 16) {
                Button { editing.toggle() } label: { Label(editing ? "Done" : "Edit order", systemImage: editing ? "checkmark" : "arrow.up.arrow.down") }
                    .buttonStyle(PillButtonStyle(height: 56, font: 22))
                if kind == .tabs || kind == .rows {
                    Button { settings.resetLayout() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PillButtonStyle(height: 56, font: 22))
                }
            }
            .padding(.bottom, 12)
            if kind == .tabs {
                ForEach(Array(settings.tabs.enumerated()), id: \.element.id) { i, t in
                    row(name: t.id.label, visible: t.visible, first: i == 0, last: i == settings.tabs.count - 1,
                        toggle: {
                            if t.visible && settings.tabs.filter(\.visible).count == 1 { return }
                            settings.tabs[i].visible.toggle()
                        },
                        move: { d in settings.move(&settings.tabs, i, by: d) })
                }
            } else {
                ForEach(Array(settings.homeRows.enumerated()), id: \.element.id) { i, r in
                    row(name: rowLabel(r.id), visible: r.visible, first: i == 0, last: i == settings.homeRows.count - 1,
                        toggle: { settings.homeRows[i].visible.toggle() },
                        move: { d in settings.move(&settings.homeRows, i, by: d) })
                }
            }
        }
    }

    private func rowLabel(_ id: String) -> String {
        if let l = settings.lists.first(where: { $0.key == id }) { return l.name + " (" + (l.t == .live ? "Live" : l.t == .film ? "Films" : "Series") + ")" }
        return HomeRow.label(id)
    }

    private func row(name: String, visible: Bool, first: Bool, last: Bool, toggle: @escaping () -> Void, move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: editing ? {} : toggle) {
                HStack(spacing: 16) {
                    Image(systemName: editing ? "line.3.horizontal" : (visible ? "eye.fill" : "eye.slash")).frame(width: 34)
                    Text(name)
                    Spacer()
                    if !editing { Text(visible ? "Shown" : "Hidden").font(.ui(20)).opacity(0.55) }
                }
                .frame(width: 720)
            }
            .buttonStyle(ChipButtonStyle(selected: visible, height: 64, idle: Color.white.opacity(0.05), dim: 0.5))
            .contextMenu {
                Button { move(-1) } label: { Label("Move up", systemImage: "arrow.up") }.disabled(first)
                Button { move(1) } label: { Label("Move down", systemImage: "arrow.down") }.disabled(last)
                Button { editing = true } label: { Label("Edit order", systemImage: "arrow.up.arrow.down") }
            }
            if editing {
                Button { withAnimation(.easeOut(duration: 0.12)) { move(-1) } } label: { Image(systemName: "arrow.up").frame(width: 40) }
                    .buttonStyle(ChipButtonStyle(height: 64, idle: Color.white.opacity(0.07), dim: 0.85)).disabled(first)
                Button { withAnimation(.easeOut(duration: 0.12)) { move(1) } } label: { Image(systemName: "arrow.down").frame(width: 40) }
                    .buttonStyle(ChipButtonStyle(height: 64, idle: Color.white.opacity(0.07), dim: 0.85)).disabled(last)
            }
        }
        .focusSection()
    }
}

/// A wrapping grid of on/off chips.
private struct ChipGrid: View {
    let items: [(id: String, label: String, sub: String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(380), spacing: 14, alignment: .leading), count: 3), alignment: .leading, spacing: 14) {
            ForEach(items, id: \.id) { it in
                Button { toggle(it.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isOn(it.id) ? "checkmark.circle.fill" : "circle").frame(width: 30)
                        Text(it.label).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(it.sub).font(.ui(18)).opacity(0.5)
                    }
                    .frame(width: 344)
                }
                .buttonStyle(ChipButtonStyle(selected: isOn(it.id), height: 60, font: 22, idle: Color.white.opacity(0.05), dim: 0.6))
            }
        }
    }
}

private struct CountriesPane: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaneTitle(title: "Live countries", note: "Countries shown in Live, Home and search, in the order you pick them. Default: Belgium, France, UK, US.")
            Text("Chosen: " + settings.countries.map(Countries.name).joined(separator: ", ")).font(.ui(22)).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 16)
            let all = catalog.liveCountries.isEmpty ? Settings.defaultCountries.map { ($0, 0) } : catalog.liveCountries
            ChipGrid(items: all.map { (id: $0.0, label: Countries.name($0.0), sub: $0.1 > 0 ? "\($0.1)" : "") },
                     isOn: { settings.countries.contains($0) },
                     toggle: { c in
                         if let i = settings.countries.firstIndex(of: c) { if settings.countries.count > 1 { settings.countries.remove(at: i) } }
                         else { settings.countries.append(c) }
                     })
            Button("Back to default") { settings.countries = Settings.defaultCountries }.buttonStyle(PillButtonStyle()).padding(.top, 24)
        }
    }
}

private struct LanguagesPane: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaneTitle(title: "Film and series languages", note: "Category groups shown in Films, Series and search. Untagged groups are Netflix, Disney+, Apple+, Top IMDB…")
            ChipGrid(items: tags.map { (id: $0.0, label: Languages.name($0.0), sub: "\($0.1)") },
                     isOn: { settings.languages.contains($0) },
                     toggle: { t in
                         if let i = settings.languages.firstIndex(of: t) { if settings.languages.count > 1 { settings.languages.remove(at: i) } }
                         else { settings.languages.append(t) }
                     })
            Text(catalog.indexState == .loading ? "Updating the search catalogue…" : "Search covers the chosen languages; it updates by itself once a day.")
                .font(.ui(20)).foregroundStyle(.white.opacity(0.5)).padding(.top, 20)
            Button("Back to default") { settings.languages = Settings.defaultLanguages }.buttonStyle(PillButtonStyle()).padding(.top, 16)
        }
    }
    private var tags: [(String, Int)] {
        var c: [String: Int] = [:]
        for x in catalog.vodCats + catalog.seriesCats { c[Clean.tag(x.name) ?? "", default: 0] += 1 }
        for d in Settings.defaultLanguages where c[d] == nil { c[d] = 0 }
        return c.sorted { a, b in
            let ia = Settings.defaultLanguages.firstIndex(of: a.key) ?? 99, ib = Settings.defaultLanguages.firstIndex(of: b.key) ?? 99
            return ia != ib ? ia < ib : a.value > b.value
        }.map { ($0.key, $0.value) }
    }
}

// MARK: - Lists: any category of the active account as a Home row

private struct ListsPane: View {
    let add: () -> Void
    @EnvironmentObject var settings: Settings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BlockTitle(title: "Lists", note: "Add any category of your account (live, films or series) as a row on Home.")
            Button(action: add) { Label("Browse all lists", systemImage: "plus") }.buttonStyle(PillButtonStyle()).padding(.bottom, 12)
            if settings.lists.isEmpty {
                Text("No lists yet.").font(.ui(22)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(settings.lists, id: \.key) { l in
                Button { settings.removeList(l.key) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: l.t == .live ? "tv" : l.t == .film ? "film" : "play.rectangle.on.rectangle").frame(width: 34)
                        Text(l.name)
                        Spacer()
                        Text("Remove").font(.ui(20)).opacity(0.55)
                    }
                    .frame(width: 900)
                }
                .buttonStyle(ChipButtonStyle(selected: true, height: 64, idle: Color.white.opacity(0.05)))
            }
        }
    }
}

private struct ListPicker: View {
    let close: () -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @State private var q = ""
    @State private var tab = 0
    @State private var all: [(list: HomeList, tag: String)] = []
    @FocusState private var fieldFocused: Bool
    private static let tabs: [(String, ItemKind?)] = [("All", nil), ("Live", .live), ("Films", .film), ("Series", .series)]

    /// Every category of the account (live, films, series), no cap.
    private func load() {
        func tag(_ name: String) -> String { Clean.tag(name) ?? Clean.country(name) ?? "" }
        func entry(_ t: ItemKind, _ c: XCategory, _ type: String) -> (list: HomeList, tag: String) {
            let tg = tag(c.name)
            return (HomeList(t: t, id: c.id, name: Clean.titleCase(Clean.category(c.name))), type + (tg.isEmpty ? "" : " · " + tg))
        }
        all = catalog.liveCats.map { entry(.live, $0, "Live") } + catalog.vodCats.map { entry(.film, $0, "Films") } + catalog.seriesCats.map { entry(.series, $0, "Series") }
    }
    private var results: [(list: HomeList, tag: String)] {
        let n = q.lowercased().trimmingCharacters(in: .whitespaces), kind = Self.tabs[tab].1
        return all.filter { (kind == nil || $0.list.t == kind) && (n.isEmpty || $0.list.name.lowercased().contains(n) || $0.tag.lowercased().contains(n)) }
    }
    private func onHome(_ l: HomeList) -> Bool { settings.lists.contains { $0.key == l.key } }

    var body: some View {
        let res = results
        VStack(alignment: .leading, spacing: 20) {
            Text("Lists").font(.ui(40, .bold))
            HStack(spacing: 20) {
                TextField("Filter: Morocco, Netflix, Kids, Sport…", text: $q).font(.ui(26)).frame(width: 760).focused($fieldFocused)
                ForEach(Self.tabs.indices, id: \.self) { t in
                    Button(Self.tabs[t].0) { tab = t }
                        .buttonStyle(ChipButtonStyle(selected: t == tab, height: 60, idle: Color.white.opacity(0.05)))
                }
                Button("Close", action: close).buttonStyle(PillButtonStyle())
            }
            .focusSection()
            Text(all.isEmpty ? "Loading every category of your account…" : "\(res.count) of \(all.count) categories  ·  ✓ = on Home  ·  select adds or removes")
                .font(.ui(20)).foregroundStyle(.white.opacity(0.5))
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(res, id: \.list.key) { r in
                        let on = onHome(r.list)
                        Button {
                            if on { settings.removeList(r.list.key); user.show("Removed from Home: " + r.list.name) }
                            else { settings.addList(r.list); user.show("Added to Home: " + r.list.name) }
                        } label: {
                            HStack {
                                Text((on ? "✓  " : "") + r.list.name).lineLimit(1)
                                Spacer()
                                Text(r.tag).font(.ui(20)).opacity(0.55)
                            }
                            .frame(width: 1100)
                        }
                        .buttonStyle(ChipButtonStyle(selected: on, height: 60, idle: Color.white.opacity(0.05)))
                    }
                }
                .padding(8)
            }
            .focusSection()
        }
        .padding(.leading, 160).padding(.top, 120)
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .focusSection()
        .onAppear { load(); fieldFocused = true }
    }
}

// MARK: - Channels: star any channel of the account (country, then group, then channel)

private struct ChannelsPane: View {
    let browse: () -> Void
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var settings: Settings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BlockTitle(title: "Channels", note: "Star any channel of your account. Starred channels go first in their country row on Home; channels of other countries go in “More favourites”.")
            Button(action: browse) { Label("Browse all channels", systemImage: "star") }.buttonStyle(PillButtonStyle()).padding(.bottom, 12)
            if user.favs.isEmpty {
                Text("No starred channels yet.").font(.ui(22)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(user.favs, id: \.item.id) { f in
                Button { user.toggleFav(f.item, cc: f.cc) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.gold).frame(width: 34)
                        Text(f.item.name).lineLimit(1)
                        Spacer()
                        Text((settings.countries.contains(f.cc) ? Countries.name(f.cc) : "More favourites") + " · Unstar").font(.ui(20)).opacity(0.55)
                    }
                    .frame(width: 900)
                }
                .buttonStyle(ChipButtonStyle(height: 64, idle: Color.white.opacity(0.05)))
            }
        }
    }
}

private struct ChannelPicker: View {
    let close: () -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @State private var countries: [(code: String, cats: [XCategory])] = []
    @State private var ci = 0
    @State private var gi = 0
    @State private var channels: [Channel]? = nil
    @FocusState private var countryFocus: Int?

    private var group: XCategory? {
        guard countries.indices.contains(ci), countries[ci].cats.indices.contains(gi) else { return nil }
        return countries[ci].cats[gi]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("Channels").font(.ui(40, .bold))
                Text("Select stars or unstars a channel. Starred channels go first on Home.").font(.ui(22)).foregroundStyle(.white.opacity(0.5))
            }
            if countries.isEmpty {
                Text("Loading every channel group…").font(.ui(24)).foregroundStyle(.white.opacity(0.5))
            } else {
                HStack(alignment: .top, spacing: 24) {
                    column(width: 240) {
                        ForEach(countries.indices, id: \.self) { i in
                            Button { pickCountry(i) } label: {
                                HStack { Text(countries[i].code); Spacer(); Text("\(countries[i].cats.count)").font(.ui(18)).opacity(0.5) }.frame(width: 190)
                            }
                            .buttonStyle(ChipButtonStyle(selected: i == ci, height: 56, font: 22))
                            .focused($countryFocus, equals: i)
                        }
                    }
                    column(width: 560) {
                        ForEach(Array(countries[ci].cats.enumerated()), id: \.element.id) { j, c in
                            Button { gi = j } label: { Text(Clean.titleCase(Clean.category(c.name))).lineLimit(1).frame(width: 510, alignment: .leading) }
                                .buttonStyle(ChipButtonStyle(selected: j == gi, height: 56, font: 22))
                                .onMoveFocus { if gi != j { gi = j } }
                        }
                    }
                    .id("groups" + countries[ci].code)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(channels.map { "\($0.count) channels" } ?? "Loading…").font(.ui(20)).foregroundStyle(.white.opacity(0.5))
                        column(width: 760) {
                            ForEach(channels ?? [], id: \.id) { ch in
                                Button { star(ch) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: user.isFav(ch.id) ? "star.fill" : "star").foregroundStyle(user.isFav(ch.id) ? Theme.gold : Color.primary.opacity(0.35))
                                        Text(ch.name).lineLimit(1)
                                        Spacer()
                                    }
                                    .frame(width: 700)
                                }
                                .buttonStyle(ChipButtonStyle(height: 56, font: 22, idle: Color.white.opacity(0.05)))
                            }
                            if channels?.isEmpty == true { Text("No channels in this group").font(.ui(22)).opacity(0.5) }
                        }
                    }
                    .id("channels" + (group?.id ?? ""))
                }
            }
        }
        .padding(.leading, 120).padding(.top, 110)
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .onChange(of: countryFocus) { _, i in if let i { pickCountry(i) } }
        .onAppear {
            // codes first, the groups without a country code last
            let all = catalog.liveByCountry()
            countries = all.filter { $0.code != "OTHER" } + all.filter { $0.code == "OTHER" }
            DispatchQueue.main.async { countryFocus = 0 }
        }
        .task(id: group?.id) {
            channels = nil
            guard let g = group else { return }
            let c = await catalog.channels(g.id)
            if g.id == group?.id { channels = c }
        }
    }

    private func pickCountry(_ i: Int) { if ci != i { ci = i; gi = 0 } }

    private func star(_ ch: Channel) {
        guard let g = group else { return }
        let code = countries[ci].code
        user.toggleFav(MediaItem(kind: .live, id: ch.id, name: ch.name, img: ch.icon, sub: Countries.name(code) + " · " + Clean.titleCase(Clean.category(g.name))), cc: code)
    }

    private func column<C: View>(width: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 6) { content() }.padding(8)
        }
        .frame(width: width, height: 840)
        .focusSection()
    }
}

// MARK: - Sources: add (the same three-way form), rename, switch, remove, choose groups

private struct AccountsPane: View {
    let add: () -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @State private var renaming: StoredAccount?
    @State private var newName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Sources", note: "Your sources, kept in this Apple TV\u{2019}s Keychain and never shown.")
            ForEach(catalog.accounts) { a in
                let active = a.id == catalog.activeId
                HStack(spacing: 16) {
                    Image(systemName: a.type.icon).font(.ui(26)).frame(width: 40, height: 40)
                        .foregroundStyle(active ? Color.green : Color.white.opacity(0.55))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.ui(26, .semibold)).lineLimit(1)
                        Text(a.note.isEmpty ? a.type.title : a.note).font(.ui(20)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if a.type == .m3u { Button("Choose groups") { catalog.chooseGroups(for: a.id) }.buttonStyle(PillButtonStyle(height: 56, font: 20, hPad: 20)) }
                    Button("Rename") { newName = a.name; renaming = a }.buttonStyle(PillButtonStyle(height: 56, font: 20, hPad: 20))
                    if active { Text("Active").font(.ui(22, .semibold)).foregroundStyle(Color.green).padding(.horizontal, 12) } else {
                        Button("Switch") { user.show("Switching to \(a.name)\u{2026}"); Task { await catalog.use(a.id, languages: settings.languages) } }
                            .buttonStyle(PillButtonStyle(height: 56, font: 20, hPad: 20))
                        Button("Remove", role: .destructive) { catalog.removeAccount(a.id); user.show("Source removed") }
                            .buttonStyle(PillButtonStyle(height: 56, font: 20, hPad: 20))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12).frame(width: 1100)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .focusSection()
            }
            Button(action: add) { Label("Add a source", systemImage: "plus") }.buttonStyle(PillButtonStyle()).padding(.top, 6)
        }
        .alert("Rename source", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let r = renaming { catalog.renameAccount(r.id, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Subtitles: the owner's OpenSubtitles account (online subtitles in the CC menu)

private struct SubtitlesPane: View {
    let edit: () -> Void
    @ObservedObject private var osub = OpenSubtitles.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Online subtitles (OpenSubtitles)", note: "With an OpenSubtitles account, the CC menu also lists online subtitles in your languages. Searching is free; each subtitle you pick uses one download.")
            if let a = osub.account {
                Text("Signed in as \(a.user)" + (osub.left.map { " · \($0) downloads left today" } ?? ""))
                    .font(.ui(24, .semibold)).padding(.bottom, 8)
                HStack(spacing: 16) {
                    Button("Change account", action: edit).buttonStyle(PillButtonStyle())
                    Button("Sign out") { osub.signOut() }.buttonStyle(PillButtonStyle())
                }
            } else {
                Text("No OpenSubtitles account.").font(.ui(22)).foregroundStyle(.white.opacity(0.55)).padding(.bottom, 8)
                Button(action: edit) { Label("Add an OpenSubtitles account", systemImage: "plus") }.buttonStyle(PillButtonStyle())
            }
        }
    }
}

private struct OSubForm: View {
    let close: () -> Void
    @State private var key = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var status = "Your API key is on opensubtitles.com › Profile › API consumers. The login is checked before it is saved."
    @State private var busy = false
    @FocusState private var first: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("OpenSubtitles account").font(.ui(40, .bold)).padding(.bottom, 10)
            field("API key") { SecureField("API key", text: $key).focused($first) }
            field("Username") { TextField("Username", text: $user).textContentType(.username) }
            field("Password") { SecureField("Password", text: $pass).textContentType(.password) }
            HStack(spacing: 18) {
                Button("Check and save") { Task { await save() } }.buttonStyle(PillButtonStyle()).disabled(busy)
                Button("Cancel", action: close).buttonStyle(PillButtonStyle())
            }
            .padding(.top, 10)
            Text(status).font(.ui(22)).foregroundStyle(.white.opacity(0.7)).frame(width: 1124, alignment: .leading)
        }
        .padding(.leading, 160).padding(.top, 150)
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .focusSection()
        .onAppear { first = true }
    }
    private func field<F: View>(_ label: String, @ViewBuilder _ f: () -> F) -> some View {
        HStack(spacing: 24) {
            Text(label).font(.ui(24, .semibold)).frame(width: 200, alignment: .leading)
            f().font(.ui(24)).frame(width: 900)
        }
    }
    private func save() async {
        let a = OSAccount(key: key.trimmingCharacters(in: .whitespaces), user: user.trimmingCharacters(in: .whitespaces), pass: pass)
        guard !a.key.isEmpty, !a.user.isEmpty, !a.pass.isEmpty else { status = "API key, username and password are all needed."; return }
        busy = true; status = "Checking the login…"
        do { try await OpenSubtitles.shared.signIn(a); busy = false; close() }
        catch { status = "OpenSubtitles refused this login (\(error.localizedDescription))."; busy = false }
    }
}

// MARK: - Search catalogue refresh (Apple TV only, under Film and series languages)

private struct CataloguePane: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BlockTitle(title: "Catalogue", note: catalog.indexState == .loading ? "Updating\u{2026}" : "\(catalog.index.films.count) films, \(catalog.index.series.count) series indexed")
            Button("Refresh now") { Task { await catalog.reload(languages: settings.languages) } }.buttonStyle(PillButtonStyle())
        }
    }
}

// MARK: - Clear lists

private struct ClearPane: View {
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @State private var confirm: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BlockTitle(title: "Clear lists", note: "Favourites, saved titles and resume points stay on this Apple TV, per account.")
            line("Favourite channels", "\(user.favs.count) channels", "Clear favourites") { confirm = "favs" }
            line("Continue watching", "\(user.continueList.count) titles", "Clear Continue watching") { confirm = "resume" }
            line("My List", "\(user.myList.count) saved", "Clear My List") { confirm = "list" }
        }
        .alert(title, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Clear", role: .destructive) {
                switch confirm { case "favs": user.clearFavs(); case "list": user.clearMyList(); default: user.clearResume() }
                confirm = nil
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        }
    }
    private var title: String {
        switch confirm { case "favs": "Clear favourite channels?"; case "list": "Clear My List?"; default: "Clear Continue watching?" }
    }
    private func line(_ t: String, _ sub: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t).font(.ui(28, .semibold))
                Text(sub).font(.ui(22)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 640, alignment: .leading)
            Button(action, action: run).buttonStyle(PillButtonStyle())
        }
        .padding(.vertical, 8)
    }
}
