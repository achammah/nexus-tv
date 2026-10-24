import SwiftUI
import AppKit

/// Layout 1a: a fixed 240 px source list on the left (search, library, Live TV by country, account, settings),
/// a toolbar with back / forward and the page title, and the page on the right.
struct LibraryWindow: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav
    @State private var onboarding = false
    @State private var window = WindowRef()
    /// The opening plays over the window at launch (the library loads underneath). A new install plays it
    /// whole and the account sheet comes in over its last frame.
    @State private var opening = OpeningGate.enabled

    var body: some View {
        ZStack {
        HStack(spacing: 0) {
            Sidebar().frame(width: 240)
            Rectangle().fill(MacTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                Toolbar()
                Rectangle().fill(Color(red: 31 / 255, green: 31 / 255, blue: 35 / 255)).frame(height: 1)
                Group {
                    if catalog.needsAccount { Color.clear }       // the account sheet sits over an empty window
                    else if let d = nav.detail { DetailPage(item: d).id(d.key) } else { page }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottom) { statusLine }
            }
            .background(MacTheme.window)
        }
        .disabled(nav.playing != nil)
        // the player fills the whole window (sidebar and toolbar hidden); the page stays underneath
        if let p = nav.playing {
            MacPlayerView(start: p, window: window) { nav.closePlayer() }
                .id(p)
                .transition(.opacity)
        }
        if catalog.needsAccount && OpeningGate.enabled {
            OpeningView(frozen: OpeningGate.frozenFrame)
        } else if opening {
            OpeningOverlay { opening = false }
        }
        }
        .animation(.easeOut(duration: 0.2), value: nav.playing)
        .background(MacTheme.window)
        .background(WindowAccessor(ref: window))
        .ignoresSafeArea()
        .task { launchHooks() }
        .sheet(isPresented: $onboarding) { AccountSheet(firstLaunch: true) { onboarding = false } }
        .onAppear {
            guard catalog.needsAccount else { return }
            if OpeningGate.enabled {
                guard OpeningGate.frozenFrame == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + OpeningSpec.homeAt) { onboarding = catalog.needsAccount }
            } else { onboarding = true }
        }
        .onChange(of: catalog.needsAccount) { _, n in onboarding = n }
    }

    /// Launch arguments for tests and screenshots: -NXWindowSize 1440x900, -NXPlay kind:id[:ext] with -NXName,
    /// -NXSeries id:name and -NXStart ms (opens the player window once the catalogue is ready).
    private func launchHooks() {
        let d = UserDefaults.standard
        if let sz = d.string(forKey: "NXWindowSize") {
            let p = sz.split(separator: "x").compactMap { Double($0) }
            if p.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let w = window.window else { return }
                    w.setContentSize(NSSize(width: p[0], height: p[1])); w.center()
                }
            }
        }
        if let o = d.string(forKey: "NXPlay") {
            let p = o.split(separator: ":").map(String.init)
            guard p.count >= 2, let k = ItemKind(rawValue: p[0]) else { return }
            var it = MediaItem(kind: k, id: p[1], name: d.string(forKey: "NXName") ?? "Test stream", ext: p.count > 2 ? p[2] : "")
            if let sr = d.string(forKey: "NXSeries") {
                let q = sr.split(separator: ":", maxSplits: 1).map(String.init)
                it.seriesId = q.first; it.seriesName = q.count > 1 ? q[1] : nil
            }
            let start = Int(d.string(forKey: "NXStart") ?? "") ?? 0
            Task {
                while catalog.state != .ready { try? await Task.sleep(nanoseconds: 200_000_000) }
                Player(nav: nav).play(it, startMs: start)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch nav.page {
        case .home: HomePage()
        case .live(let cc): if cc.isEmpty { LivePage(country: cc) } else { LiveBrowsePage(country: cc) }
        case .films: BrowsePage(kind: .film)
        case .series: BrowsePage(kind: .series)
        case .list(let r): BrowseListPage(ref: r)
        case .family(let r): BrowseFamilyPage(ref: r)
        case .mylist: MyListPage()
        case .search: SearchPage()
        case .account: AccountPage()
        case .settings: ScrollView { MacSettingsPane().padding(24) }
        }
    }

    /// Search index after sign-in, and load errors: a small line at the bottom, nothing waits for it.
    @ViewBuilder private var statusLine: some View {
        if let p = catalog.indexProgress {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(p).font(.system(size: 12)) }
                .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color.black.opacity(0.85)))
                .padding(.bottom, 14)
        } else if case .failed(let msg) = catalog.state, !catalog.needsAccount {
            Text(msg).font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.85))).padding(.bottom, 14)
        }
    }
}

private struct Toolbar: View {
    @EnvironmentObject var nav: MacNav
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Button { nav.goBack() } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .disabled(!nav.canBack).accessibilityLabel("Back").keyboardShortcut("[", modifiers: .command)
                Button { nav.goForward() } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                    .disabled(!nav.canForward).accessibilityLabel("Forward").keyboardShortcut("]", modifiers: .command)
            }
            .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(MacTheme.soft)
            if let d = nav.detail {
                Text(nav.page.title + " ›").font(.system(size: 13)).foregroundStyle(MacTheme.dim)
                Text(d.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
            } else {
                Text(nav.page.title).font(.system(size: 15, weight: .bold))
                BrowseCrumb()
            }
            Spacer()
            if nav.detail == nil, nav.page == .films || nav.page == .series { LanguageMenu() }
        }
        .padding(.horizontal, 20).frame(height: 52)
    }
}

private struct Sidebar: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Wordmark().padding(.horizontal, 8).padding(.bottom, 16)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(MacTheme.dim)
                TextField("Search everything", text: $nav.query)
                    .textFieldStyle(.plain).font(.system(size: 12.5)).focused($searchFocused)
                    .onSubmit { nav.go(.search) }
                    .accessibilityIdentifier("search-field")
                Text("⌘F").font(.system(size: 10, weight: .medium)).foregroundStyle(MacTheme.dim)
                    .padding(.horizontal, 4).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(MacTheme.dim, lineWidth: 1))
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.field))
            .padding(.bottom, 14)
            .onChange(of: nav.query) { _, q in if !q.isEmpty, nav.page != .search || nav.detail != nil { nav.go(.search) } }
            .onChange(of: nav.focusSearch) { _, _ in searchFocused = true }

            heading("Library")
            item("house", "Home", .home)
            item("tv", "Live TV", .live(""))
            item("film", "Films", .films)
            item("rectangle.stack", "Series", .series)
            item("bookmark", "My List", .mylist)

            heading("Live TV by country")
            ForEach(settings.countries, id: \.self) { cc in
                CountrySideRow(code: cc, name: Countries.name(cc), count: count(cc), selected: nav.detail == nil && nav.page.root == .live(cc)) { nav.go(.live(cc)) }
            }
            Spacer()
            Rectangle().fill(MacTheme.line).frame(height: 1).padding(.bottom, 8)
            item("person", "IPTV account", .account)
            item("gearshape", "Settings", .settings, trailing: "⌘,")
        }
        .padding(.horizontal, 12).padding(.top, 52).padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MacTheme.sidebar)
    }

    /// Channels of the country once the whole live list is loaded; until then its number of groups.
    private func count(_ cc: String) -> String {
        let groups = catalog.liveGroups(cc)
        if !catalog.liveIndex.isEmpty {
            let n = groups.reduce(0) { $0 + (catalog.liveIndex[$1.id]?.count ?? 0) }
            return n.formatted(.number)
        }
        return groups.isEmpty ? "" : "\(groups.count) groups"
    }

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.45))
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 6)
    }
    private func item(_ icon: String, _ label: String, _ p: MacNav.Page, trailing: String? = nil) -> some View {
        let on = nav.detail == nil && nav.page.root == p
        return row(selected: on, id: "side:" + label) {
            Image(systemName: icon).font(.system(size: 14)).frame(width: 20)
            Text(label)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(on ? Color.black.opacity(0.5) : MacTheme.dim) }
        } action: { if p == .settings { nav.go(.settings) } else { nav.go(p) } }
    }
    private func row<C: View>(selected: Bool, id: String, @ViewBuilder _ content: () -> C, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) { content() }
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : Color(red: 230 / 255, green: 230 / 255, blue: 234 / 255))
                .padding(.horizontal, 9).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One "Live TV by country" row: code, name, channel count. On the white selection every part turns dark
/// (the code and the count were white on white before).
struct CountrySideRow: View {
    let code: String, name: String, count: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(code).font(.system(size: 11, weight: .bold)).foregroundStyle(selected ? Color.black.opacity(0.55) : MacTheme.dim).frame(width: 22)
                Text(name)
                Spacer()
                Text(count).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(selected ? Color.black.opacity(0.55) : MacTheme.dim)
            }
            .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.black : Color(red: 230 / 255, green: 230 / 255, blue: 234 / 255))
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("side:live:" + code)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
