import SwiftUI

// The seven panes of the Settings page. Every setting of the old page is here; none changes what it does.

enum SettingsOverlay: Equatable { case addList, channels(String?), osub, countries, languages }

// MARK: - Account & sources

struct AccountPane: View {
    let open: (SettingsOverlay) -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @State private var renaming: StoredAccount?
    @State private var newName = ""

    private var active: StoredAccount? { catalog.accounts.first { $0.id == catalog.activeId } ?? catalog.accounts.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "Active source")
            SGroup {
                if let a = active { sourceRow(a, isActive: true) } else { SInfo(title: "No source yet") { EmptyView() } }
            }
            SHeader(text: "Other sources")
            SGroup {
                ForEach(catalog.accounts.filter { $0.id != active?.id }) { a in sourceRow(a, isActive: false) }
                SRow(title: "Add a source", action: { catalog.addingSource = true }) {
                    Text("Xtream login · M3U playlist · Stalker portal")
                }
            }
            SHeader(text: "Catalogue")
            SGroup {
                SRow(title: "Refresh catalogue",
                     help: catalog.indexState == .loading ? "Updating\u{2026}" : "\(catalog.index.films.count) films, \(catalog.index.series.count) series indexed",
                     action: { Task { await catalog.reload(languages: settings.languages) } }) { Text("Refresh now") }
            }
        }
        .alert("Rename source", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let r = renaming { catalog.renameAccount(r.id, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func help(_ a: StoredAccount, isActive: Bool) -> String {
        var parts: [String] = []
        if isActive, catalog.index.films.count + catalog.index.series.count > 0 {
            parts.append("\(catalog.index.films.count) films · \(catalog.index.series.count) series")
        } else { parts.append(a.note.isEmpty ? a.type.title : a.note) }
        if let g = a.groups { parts.append("\(g.count) groups chosen") }
        return parts.joined(separator: " · ")
    }

    private func sourceRow(_ a: StoredAccount, isActive: Bool) -> some View {
        SRowLabel(title: a.name, help: help(a, isActive: isActive)) {
            SBadge(text: a.type.badge.text, fill: a.type.badge.fill)
            if isActive { Text("Active").font(.ui(24, .semibold)).foregroundStyle(Color.green) }
            if !isActive {
                Button("Switch") { user.show("Switching to \(a.name)\u{2026}"); Task { await catalog.use(a.id, languages: settings.languages) } }
                    .buttonStyle(SettingsPillStyle())
            }
            if a.type == .m3u { Button("Choose groups") { catalog.chooseGroups(for: a.id) }.buttonStyle(SettingsPillStyle()) }
            Button("Rename") { newName = a.name; renaming = a }.buttonStyle(SettingsPillStyle())
            if !isActive {
                Button("Remove") { catalog.removeAccount(a.id); user.show("Source removed") }.buttonStyle(SettingsPillStyle(destructive: true))
            }
        }
        .focusSection()
    }
}

// MARK: - Channels

struct ChannelsPane: View {
    let open: (SettingsOverlay) -> Void
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "Countries on Live and Home")
            SGroup {
                SRow(title: "Pinned countries", help: "Shown first on Live, each with its own row on Home", action: { open(.countries) }) {
                    HStack(spacing: -10) {
                        ForEach(Array(settings.countries.prefix(5)), id: \.self) { cc in
                            if let asset = CountryNames.flagAsset(cc) {
                                Image(asset).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(Circle())
                                    .overlay(Circle().stroke(Color(red: 0.08, green: 0.08, blue: 0.10), lineWidth: 3))
                            }
                        }
                    }
                    Text("\(settings.countries.count)").font(.ui(24, .medium)).foregroundStyle(.white)
                }
            }
            SHeader(text: "Starred channels")
            SGroup {
                ForEach(settings.countries, id: \.self) { cc in
                    let favs = user.favs.filter { $0.cc == cc }
                    SRow(title: Countries.name(cc), help: summary(favs), action: { open(.channels(cc)) }) {
                        if favs.isEmpty { Text("Browse channels") } else { starCount(favs.count) }
                    }
                }
                let other = user.favs.filter { !settings.countries.contains($0.cc) }
                if !other.isEmpty {
                    SRow(title: "More favourites", help: summary(other), action: { open(.channels(other.first?.cc)) }) { starCount(other.count) }
                }
                SRow(title: "Browse all channels", help: "Star any channel of your account: country, then group, then channel", action: { open(.channels(nil)) }) { EmptyView() }
            }
        }
    }

    private func starCount(_ n: Int) -> some View {
        HStack(spacing: 6) { Text("\(n)").foregroundStyle(.white); Image(systemName: "star.fill").foregroundStyle(Theme.gold) }.font(.ui(24, .medium))
    }
    private func summary(_ favs: [Favourite]) -> String {
        if favs.isEmpty { return "None yet" }
        let names = favs.prefix(4).map { $0.item.name }.joined(separator: ", ")
        return favs.count > 4 ? names + " + \(favs.count - 4)" : names
    }
}

// MARK: - Home & views

struct HomePane: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "Home rows · in order")
            SGroup {
                ForEach(Array(settings.homeRows.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 12) {
                        Button { settings.homeRows[i].visible.toggle() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(r.id)).font(.ui(28)).lineLimit(1)
                                if r.id.hasPrefix("live:") { Text("Live now").font(.ui(20)).foregroundStyle(.white.opacity(0.45)) }
                            }
                            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                        }
                        .buttonStyle(SettingsRowStyle())
                        .contextMenu {
                            Button { settings.move(&settings.homeRows, i, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }.disabled(i == 0)
                            Button { settings.move(&settings.homeRows, i, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }.disabled(i == settings.homeRows.count - 1)
                        }
                        Text("Move").font(.ui(24)).foregroundStyle(.white.opacity(0.55))
                        Button { withAnimation(.easeOut(duration: 0.12)) { settings.move(&settings.homeRows, i, by: -1) } } label: { Image(systemName: "arrowtriangle.up.fill") }
                            .buttonStyle(SettingsPillStyle()).disabled(i == 0)
                        Button { withAnimation(.easeOut(duration: 0.12)) { settings.move(&settings.homeRows, i, by: 1) } } label: { Image(systemName: "arrowtriangle.down.fill") }
                            .buttonStyle(SettingsPillStyle()).disabled(i == settings.homeRows.count - 1)
                        SToggle(on: r.visible)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                    .focusSection()
                }
            }
            SHeader(text: "Menu tabs")
            SGroup {
                SInfo(title: "Tabs shown in the top menu", help: "Select shows or hides a tab. Hold to move it left or right. Settings always stays last.") { EmptyView() }
                HStack(spacing: 12) {
                    ForEach(Array(settings.tabs.enumerated()), id: \.element.id) { i, t in
                        Button {
                            if t.visible && settings.tabs.filter(\.visible).count == 1 { return }
                            settings.tabs[i].visible.toggle()
                        } label: { Text(t.id.label) }
                        .buttonStyle(SettingsPillStyle(on: t.visible))
                        .contextMenu {
                            Button { settings.move(&settings.tabs, i, by: -1) } label: { Label("Move left", systemImage: "arrow.left") }.disabled(i == 0)
                            Button { settings.move(&settings.tabs, i, by: 1) } label: { Label("Move right", systemImage: "arrow.right") }.disabled(i == settings.tabs.count - 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .focusSection()
            }
            SHeader(text: "Layout")
            SGroup {
                SRow(title: "Reset layout", help: "Back to the default menu tabs, Home rows and tile order", chevron: false, action: { settings.resetLayout() }) { Text("Reset") }
            }
        }
    }

    private func title(_ id: String) -> String {
        if let l = settings.lists.first(where: { $0.key == id }) { return l.name + " (" + (l.t == .live ? "Live" : l.t == .film ? "Films" : "Series") + ")" }
        if id.hasPrefix("live:") { return Countries.name(String(id.dropFirst(5))) }
        return HomeRow.label(id)
    }
}

// MARK: - Lists

struct ListsPane: View {
    let open: (SettingsOverlay) -> Void
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "Home lists")
            SGroup {
                SRow(title: "Browse all lists", help: "Add any category of your account (live, films or series) as a row on Home", action: { open(.addList) }) { Text("Add") }
                if settings.lists.isEmpty { SInfo(title: "No lists yet") { EmptyView() } }
                ForEach(settings.lists, id: \.key) { l in
                    SRow(title: l.name, help: l.t == .live ? "Live" : l.t == .film ? "Films" : "Series", chevron: false, action: { settings.removeList(l.key) }) { Text("Remove") }
                }
            }
        }
    }
}

// MARK: - Playback & subtitles

struct PlaybackPane: View {
    let open: (SettingsOverlay) -> Void
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @ObservedObject private var osub = OpenSubtitles.shared

    /// What the player remembers from the last pick (UserStore keeps it under "*"); read-only here.
    static func lastPick(_ user: UserStore) -> TrackPref? { user.trackPref(MediaItem(kind: .film, id: "settings-last-pick", name: "")) }
    static func langName(_ code: String) -> String { Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased() }

    var body: some View {
        let pick = Self.lastPick(user)
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "Audio")
            SGroup {
                SInfo(title: "Audio language", help: "The language you picked last in the player; a title never set takes it") {
                    Text(pick?.audioLang.map(Self.langName) ?? "Not picked yet").foregroundStyle(.white)
                }
            }
            SHeader(text: "Subtitles")
            SGroup {
                SInfo(title: "Subtitles", help: "Your last choice in the player") {
                    Text(subtitleValue(pick)).foregroundStyle(.white)
                }
                SRow(title: "Film and series languages", help: "Which catalogue lists you see in Films, Series and search", action: { open(.languages) }) {
                    Text(settings.languages.map { $0.isEmpty ? "Untagged" : Languages.name($0) }.joined(separator: ", ")).lineLimit(1)
                }
            }
            SHeader(text: "OpenSubtitles")
            SGroup {
                if let a = osub.account {
                    SRow(title: "Change account", help: "Online subtitles when a file has none, aligned to the speech", action: { open(.osub) }) {
                        SBadge(text: "Signed in", fill: Color(red: 0.12, green: 0.56, blue: 0.29))
                        Text("Signed in as \(a.user)" + (osub.left.map { " · \($0) downloads left today" } ?? ""))
                    }
                    SRow(title: "Sign out", chevron: false, action: { osub.signOut() }) { EmptyView() }
                } else {
                    SRow(title: "Add an OpenSubtitles account", help: "With an account, the CC menu also lists online subtitles in your languages. Each pick uses one download.", action: { open(.osub) }) {
                        Text("No account")
                    }
                }
            }
        }
    }

    private func subtitleValue(_ p: TrackPref?) -> String {
        guard let p else { return "Not picked yet" }
        if p.subOff == true { return "Off" }
        if let l = p.subLang ?? p.subOnline { return Self.langName(l) }
        return "Not picked yet"
    }
}

// MARK: - Data & storage

struct DataPane: View {
    @EnvironmentObject var user: UserStore
    @State private var confirm: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "On this Apple TV, per source")
            SGroup {
                SRow(title: "Clear favourites", help: "\(user.favs.count) starred channels", chevron: false, action: { confirm = "favs" }) { Text("Clear") }
                SRow(title: "Clear Continue watching", help: "\(user.continueList.count) titles", chevron: false, action: { confirm = "resume" }) { Text("Clear") }
                SRow(title: "Clear My List", help: "\(user.myList.count) saved", chevron: false, action: { confirm = "list" }) { Text("Clear") }
            }
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
}

// MARK: - About

struct AboutPane: View {
    @EnvironmentObject var catalog: Catalog

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SHeader(text: "This app")
            SGroup {
                SInfo(title: "Version") { Text(Self.version + (Self.build.isEmpty ? "" : " (\(Self.build))")).foregroundStyle(.white) }
                SInfo(title: "Active source", help: "Kept in this Apple TV\u{2019}s Keychain and never shown") { Text(catalog.activeName).foregroundStyle(.white) }
            }
        }
    }
}
