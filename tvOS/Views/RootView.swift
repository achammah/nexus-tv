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
    /// The opening plays over Home at launch (Home loads underneath); a new install plays it under the account form.
    @State private var opening = OpeningGate.enabled
    @StateObject private var onboard = OnboardingModel.fromLaunch()
    /// The first-launch screen, "Add a source", a check in progress, or a debug capture.
    private var showsOnboarding: Bool { catalog.showsOnboarding || catalog.addingSource || onboard.isActive }

    var body: some View {
        let _ = Metrics.shared.count("RootView")
        ZStack(alignment: .topLeading) {
            Color.black
            Group {
            // Tabs stay alive once opened so each keeps its place; hidden ones are disabled (not focusable).
            ForEach(TabID.allCases) { t in
                if visited.contains(t) || t == nav.tab {
                    let on = t == nav.tab && nav.detail.isEmpty && nav.browse.isEmpty
                    screen(t)
                        .opacity(on ? 1 : 0)
                        .disabled(!on || showsOnboarding || opening)   // the opening holds the remote until it ends or is skipped
                        .accessibilityHidden(!on)
                }
            }
            // opened lists and families stay alive under the one on top, so Menu lands back on the card it left
            ForEach(Array(nav.browse.enumerated()), id: \.offset) { i, b in
                let top = i == nav.browse.count - 1 && nav.detail.isEmpty
                BrowseTVPage(ref: b, top: top).id(b)
                    .opacity(top ? 1 : 0)
                    .disabled(!top || showsOnboarding || opening)
                    .accessibilityHidden(!top)
            }
            if let d = nav.detail.last {
                DetailView(item: d).id(d.key)
            }
            header.disabled(showsOnboarding || opening)
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
            }
            // Home rises from a slight zoom and blur while the two halves slide apart (about 1.2 s)
            .opacity(showsOnboarding && !onboard.ending ? 0 : 1)
            .scaleEffect(onboard.ending || !showsOnboarding ? 1 : 1.06)
            .blur(radius: onboard.ending || !showsOnboarding ? 0 : 14)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.2).delay(0.2), value: onboard.ending)
            .animation(.easeOut(duration: 0.9).delay(0.25), value: showsOnboarding && !onboard.ending)
            if catalog.needsAccount && catalog.onboardingSkipped && !catalog.addingSource && !onboard.isActive && nav.tab != .settings {
                // after "Skip for now": Home and the other screens say the library is empty
                ZStack { Color.black; LibraryEmptyState { catalog.onboardingSkipped = false } }.padding(.top, 128)
            }
            if showsOnboarding { OnboardingView(model: onboard).transition(.opacity) }
            if let st = catalog.picker { GroupPickerView(state: st).frame(width: 1920, height: 1080) }
            if let f = catalog.streamProgress {
                GeometryReader { g in Rectangle().fill(LinearGradient(colors: [Color(red: 211 / 255, green: 148 / 255, blue: 230 / 255), Color(red: 174 / 255, green: 219 / 255, blue: 142 / 255)], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * f, height: 3) }
                    .frame(height: 3).frame(maxHeight: .infinity, alignment: .top).allowsHitTesting(false)
            }
            if opening && !catalog.needsAccount && !onboard.isActive { OpeningOverlay { opening = false } }
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
        if !nav.browse.isEmpty { return { nav.browse.removeLast() } }
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
        case .live: LiveBrowseTVView()
        case .films: BrowseTVView(kind: .film)
        case .series: BrowseTVView(kind: .series)
        case .mylist: MyListView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }

    // MARK: header: brand, centred frosted menu, clock

    private var header: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Image("Lockup").resizable().scaledToFit().frame(height: 26).opacity(0.82)      // the mark and "tv" (the opening's last frame), small and quiet
                    .accessibilityLabel("Nexus TV")
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
