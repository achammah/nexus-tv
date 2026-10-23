import SwiftUI

struct RootView: View {
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @FocusState private var menuFocus: TabID?
    @Namespace private var rootScope
    @Environment(\.resetFocus) private var resetFocus
    @ObservedObject private var toaster = Toaster.shared
    @ObservedObject private var chrome = Chrome.shared
    @State private var visited: Set<TabID> = []

    var body: some View {
        let _ = Metrics.shared.count("RootView")
        ZStack(alignment: .topLeading) {
            Color.black
            // Tabs stay alive once opened so each keeps its place; hidden ones are disabled (not focusable).
            ForEach(TabID.allCases) { t in
                if visited.contains(t) || t == nav.tab {
                    let on = t == nav.tab && nav.detail.isEmpty
                    screen(t)
                        .opacity(on ? 1 : 0)
                        .disabled(!on || catalog.needsAccount)
                        .accessibilityHidden(!on)
                }
            }
            if let d = nav.detail.last {
                DetailView(item: d).id(d.key)
            }
            header.disabled(catalog.needsAccount)
            if case .failed(let msg) = catalog.state, nav.tab != .settings, !catalog.needsAccount {
                Text(msg).font(.ui(24)).foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 30).padding(.vertical, 16).background(Capsule().fill(Theme.glass))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 60)
            }
            // first search index after sign-in: a small line, nothing waits for it
            if let p = catalog.indexProgress, !catalog.needsAccount {
                HStack(spacing: 12) { ProgressView().scaleEffect(0.6); Text(p).font(.ui(20)) }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black))   // solid: readable over tiles
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Theme.x0).padding(.bottom, 40)
                    .allowsHitTesting(false)
            }
            if catalog.needsAccount { OnboardingView() }
            if let t = toaster.text {
                Toast(text: t).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 80)
                    .transition(.opacity).allowsHitTesting(false)
            }
        }
        .frame(width: 1920, height: 1080)
        .focusScope(rootScope)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.3), value: toaster.text)
        .onChange(of: nav.tab, initial: true) { _, t in visited.insert(t); Metrics.shared.mark("tab:" + t.rawValue) }
        // after Home is up: fetch the first page of each screen, so opening it shows content at once.
        // (Building the screens hidden in advance was measured: it doubled the cost of every Home move, so it is not done.)
        .task(id: catalog.state == .ready) {
            guard catalog.state == .ready else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await catalog.prewarm(country: settings.countries.first ?? "BE", languages: settings.languages)
        }
        // Entering the menu from the page lands on the current tab (like the tvOS tab bar);
        // moving along the menu switches tabs.
        .onChange(of: menuFocus) { old, f in
            guard let f, nav.detail.isEmpty else { return }
            if old == nil && f != nav.tab { menuFocus = nav.tab } else { nav.tab = f }
        }
        // a plain assignment is refused while focus is deep in a scrolled screen; a focus reset to the
        // scope's preferred item (the current tab) is not
        .onChange(of: nav.focusMenuTick) { _, _ in
            // the header must be drawn before it can take focus; the black band under it stays (chrome.scrolled)
            chrome.headerHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { menuFocus = nav.tab; resetFocus(in: rootScope) }
        }
        .onExitCommand(perform: exitAction)
        .fullScreenCover(item: $nav.playing) { req in
            PlayerScreen(request: req).environmentObject(catalog).environmentObject(user)
        }
    }

    /// Menu/Back: close the detail page, else go up to the menu bar, else back to Home, else leave the app (system default).
    private var exitAction: (() -> Void)? {
        if nav.movingRow != nil { return { nav.stopMoving() } }
        if !nav.detail.isEmpty { return { nav.detail.removeLast() } }
        // Menu from the content goes up to the tab bar. A plain focus assignment is refused while focus is deep
        // in a scrolled screen, so this resets focus to the scope's preferred item, the current tab. On a scrolled
        // Home the header shows because the menu has focus; the black band under it stays (headerHidden stays set).
        if menuFocus == nil { return { nav.focusMenuTick += 1 } }
        if nav.tab != .home { return { nav.tab = .home; menuFocus = .home } }
        return nil
    }

    @ViewBuilder
    private func screen(_ t: TabID) -> some View {
        switch t {
        case .home: HomeView()
        case .live: GuideView()
        case .films: LibraryView(kind: .film)
        case .series: LibraryView(kind: .series)
        case .mylist: MyListView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }

    // MARK: header: brand, centred frosted menu, clock

    private var header: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Image("NexusLogo").resizable().scaledToFit().frame(height: 40).padding(.top, 2)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 2, height: 32).padding(.leading, 18).padding(.trailing, 16)
                Text("TV").font(.ui(36, .light)).tracking(3)
                Spacer()
                TimelineView(.periodic(from: .now, by: 10)) { ctx in
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.ui(34, .light)).tracking(1).monospacedDigit()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, Theme.x0)
            .padding(.top, 62)

            if nav.detail.isEmpty {
                // a full-width band: Up from anywhere below (a tile on the far left or right) lands in the menu
                HStack(spacing: 0) { Spacer(minLength: 0); menu; Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity)
                    .focusSection()
                    .padding(.top, 58)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(headerVisible ? 1 : 0.001)   // not 0: a fully transparent header drops out of the accessibility tree and stays out
        .animation(.easeOut(duration: 0.15), value: headerVisible)
    }

    /// Home hides the header while rows pass under it; it comes back when the menu takes focus.
    private var headerVisible: Bool { !(nav.tab == .home && nav.detail.isEmpty && chrome.headerHidden && menuFocus == nil) }

    private var menu: some View {
        HStack(spacing: 4) {
            ForEach(settings.visibleTabs) { t in
                Button { nav.tab = t } label: {
                    HStack(spacing: 8) {
                        if let i = t.icon { Image(systemName: i).font(.ui(21, .bold)) }
                        if t != .settings { Text(t.label) }
                    }
                }
                .buttonStyle(ChipButtonStyle(selected: t == nav.tab, height: 44, radius: 22, font: 23, hPad: t == .settings ? 14 : 24,
                                             onFill: Color.white.opacity(0.16), dim: 0.62))
                .focused($menuFocus, equals: t)
                .prefersDefaultFocus(t == nav.tab, in: rootScope)
                .accessibilityLabel(t.label)      // the Settings tab is an icon: VoiceOver says "Settings", not the symbol name
            }
        }
        .padding(6)
        .background(Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.094).opacity(0.86)))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .focusSection()
    }
}
