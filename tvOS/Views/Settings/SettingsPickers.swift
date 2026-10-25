import SwiftUI

// The full-screen pickers the Settings page opens: the list browser, the channel browser and the OpenSubtitles form (as they were), plus the countries and languages pickers.

struct ListPicker: View {
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

struct ChannelPicker: View {
    let close: () -> Void
    /// The country the browser opens on (a row of Starred channels); nil = the first.
    var start: String? = nil
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
            let first = countries.firstIndex { $0.code == start } ?? 0
            ci = first; gi = 0
            DispatchQueue.main.async { countryFocus = first }
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

struct OSubForm: View {
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

/// Pinned countries: the chips of the old Live countries section, in a full-screen picker.
struct CountriesPicker: View {
    let close: () -> Void
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pinned countries").font(.ui(40, .bold))
            Text("Shown first on Live, each with its own row on Home, in the order you pick them. Default: Belgium, France, UK, US.")
                .font(.ui(22)).foregroundStyle(.white.opacity(0.55))
            Text("Chosen: " + settings.countries.map(Countries.name).joined(separator: ", ")).font(.ui(22)).foregroundStyle(.white.opacity(0.8))
            ScrollView(.vertical, showsIndicators: false) {
                let all = catalog.liveCountries.isEmpty ? Settings.defaultCountries.map { ($0, 0) } : catalog.liveCountries
                ChipGrid(items: all.map { (id: $0.0, label: Countries.name($0.0), sub: $0.1 > 0 ? "\($0.1)" : "") },
                         isOn: { settings.countries.contains($0) },
                         toggle: { c in
                             if let i = settings.countries.firstIndex(of: c) { if settings.countries.count > 1 { settings.countries.remove(at: i) } }
                             else { settings.countries.append(c) }
                         })
                .padding(8)
            }
            .focusSection()
            HStack(spacing: 18) {
                Button("Back to default") { settings.countries = Settings.defaultCountries }.buttonStyle(PillButtonStyle())
                Button("Done", action: close).buttonStyle(PillButtonStyle())
            }
        }
        .padding(.leading, 120).padding(.top, 110)
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .focusSection()
    }
}

/// Film and series languages: the chips of the old section, in a full-screen picker.
struct LanguagesPicker: View {
    let close: () -> Void
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Film and series languages").font(.ui(40, .bold))
            Text("Category groups shown in Films, Series and search. Untagged groups are Netflix, Disney+, Apple+, Top IMDB…")
                .font(.ui(22)).foregroundStyle(.white.opacity(0.55))
            ScrollView(.vertical, showsIndicators: false) {
                ChipGrid(items: tags.map { (id: $0.0, label: Languages.name($0.0), sub: "\($0.1)") },
                         isOn: { settings.languages.contains($0) },
                         toggle: { t in
                             if let i = settings.languages.firstIndex(of: t) { if settings.languages.count > 1 { settings.languages.remove(at: i) } }
                             else { settings.languages.append(t) }
                         })
                .padding(8)
            }
            .focusSection()
            Text(catalog.indexState == .loading ? "Updating the search catalogue…" : "Search covers the chosen languages; it updates by itself once a day.")
                .font(.ui(20)).foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 18) {
                Button("Back to default") { settings.languages = Settings.defaultLanguages }.buttonStyle(PillButtonStyle())
                Button("Done", action: close).buttonStyle(PillButtonStyle())
            }
        }
        .padding(.leading, 120).padding(.top, 110)
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .focusSection()
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

/// A wrapping grid of on/off chips (countries, languages).
struct ChipGrid: View {
    let items: [(id: String, label: String, sub: String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(380), spacing: 14, alignment: .leading), count: 4), alignment: .leading, spacing: 14) {
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
