import SwiftUI

/// Live TV: countries + categories (left), channels with logos (middle), preview (right).
struct GuideView: View {
    /// Opened from a Live TV card: the country and the list to show first.
    var start: (cc: String, group: String)? = nil
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: Nav
    @State private var cc = ""
    @State private var catId = ""
    @State private var channels: [Channel] = []
    @State private var loading = false
    /// The channel shown in the preview. A reference kept in @State: moving along the list updates only the preview,
    /// never the whole guide (measured: the whole guide redrawing on every move was the cost of a channel move).
    @State private var sel = GuideSelection()
    private var current: Int { get { sel.current } nonmutating set { sel.current = newValue } }
    @State private var pendingCat: Task<Void, Never>?

    private var groups: [XCategory] { catalog.liveGroups(cc) }
    private var group: XCategory? { groups.first { $0.id == catId } }
    private var groupLabel: String { group.map { Clean.titleCase(Clean.category($0.name)) } ?? "" }


    var body: some View {
        let _ = Metrics.shared.count("GuideView")
        ZStack(alignment: .topLeading) {
            Color.black
            // columns side by side (never overlapping frames, so the focus engine moves cleanly between them)
            HStack(alignment: .top, spacing: 20) {
                left.frame(width: 400, height: 840).background(Glass())
                middle.frame(width: 680, height: 840).background(Glass())
                preview.frame(width: 576, height: 840).background(Glass()).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.leading, 112).padding(.top, 150)
            Text("Click to watch  ·  swipe ← → between columns  ·  while watching, swipe ↑ ↓ to change channel")
                .font(.ui(20)).foregroundStyle(.white.opacity(0.42)).padding(.leading, 112).padding(.top, 1010)
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .onAppear {
            if let s = start, catId.isEmpty { selectCountry(s.cc); selectCategory(s.group); return }
            if let g = nav.guideCountry { nav.guideCountry = nil; selectCountry(g) }
            else if cc.isEmpty || !settings.countries.contains(cc) { selectCountry(settings.countries.first ?? "BE") }
        }
        .onChange(of: nav.guideCountry) { _, g in if let g { nav.guideCountry = nil; selectCountry(g) } }
        .onChange(of: catalog.liveCats.count) { _, _ in if catId.isEmpty { selectCountry(cc.isEmpty ? (settings.countries.first ?? "BE") : cc) } }
        .onChange(of: settings.countries) { _, c in if !c.contains(cc) { selectCountry(c.first ?? "BE") } }
    }

    private func selectCountry(_ c: String) {
        guard c != cc || catId.isEmpty else { return }
        cc = c
        if let first = catalog.liveGroups(c).first { selectCategory(first.id) } else { catId = ""; channels = [] }
    }

    private func selectCategory(_ id: String) {
        guard id != catId else { return }
        catId = id; current = 0; loading = true
        Task {
            let list = await catalog.channels(id)
            if catId == id { channels = list; loading = false; Metrics.shared.mark("ready:live") }
        }
    }

    // MARK: left: countries + categories

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(settings.countries, id: \.self) { c in
                    Button { selectCountry(c) } label: { Text(Countries.name(c)) }
                        .buttonStyle(ChipButtonStyle(selected: c == cc, height: 44, radius: 22, font: 20, hPad: 15,
                                                     idle: Color.white.opacity(0.07), onFill: Color.white.opacity(0.2), dim: 0.68))
                        .onMoveFocus { selectCountry(c) }
                }
            }
            .padding(.leading, 18).padding(.top, 24)
            .focusSection()

            SectionLabel(text: "Categories").padding(.leading, 32).padding(.top, 30).padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { g in
                        Button { selectCategory(g.id) } label: {
                            HStack {
                                Text(Clean.titleCase(Clean.category(g.name))).lineLimit(1)
                                Spacer(minLength: 12)
                                if let n = catalog.liveIndex[g.id]?.count { Text("\(n)").font(.ui(19)).opacity(0.55) }
                            }
                            .frame(width: 328)
                        }
                        .buttonStyle(ChipButtonStyle(selected: g.id == catId))
                        .onMoveFocus { pendingCat?.cancel(); pendingCat = Task { try? await Task.sleep(nanoseconds: 350_000_000); if !Task.isCancelled { selectCategory(g.id) } } }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 4)
            }
            .frame(height: 690)
            .focusSection()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: middle: channels

    private var middle: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: group == nil ? "" : "\(groupLabel)  ·  \(channels.count) channels").padding(.leading, 32).padding(.top, 30).padding(.bottom, 18)
            if loading || (channels.isEmpty && catalog.liveCats.isEmpty) {
                VStack(spacing: 18) { ForEach(0..<8, id: \.self) { _ in Skeleton(radius: 16).frame(width: 640, height: 60) } }
                    .padding(.horizontal, 20).padding(.top, 4)
            } else if channels.isEmpty {
                EmptyNote(text: catalog.liveCats.isEmpty ? "Loading channels…" : "No channels").padding(.leading, 32).padding(.top, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(channels.enumerated()), id: \.element.id) { i, c in
                            Button { play(i) } label: { ChannelRow(n: i + 1, channel: c, fav: user.isFav(c.id)) }
                                .buttonStyle(RowButtonStyle())
                                .onMoveFocus { current = i }
                                .contextMenu {
                                    Button { user.toggleFav(item(c), cc: cc) } label: {
                                        user.isFav(c.id) ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
                                    }
                                    Button { user.toggle(item(c)) } label: {
                                        user.inList(item(c)) ? Label("Remove from My List", systemImage: "minus.circle") : Label("Add to My List", systemImage: "plus")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .frame(height: 740)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }

    // MARK: right: preview

    private var preview: some View {
        GuidePreview(sel: sel, channels: channels, cc: cc, groupLabel: groupLabel, play: play)
    }

    private func item(_ c: Channel) -> MediaItem {
        MediaItem(kind: .live, id: c.id, name: c.name, img: c.icon, sub: Countries.name(cc) + " · " + groupLabel)
    }

    private func play(_ i: Int) {
        guard channels.indices.contains(i) else { return }
        current = i
        let list = channels.map(item)
        nav.play(list[i], list: list, index: i, subtitle: list[i].sub)
    }
}

final class GuideSelection: ObservableObject { @Published var current = 0 }

struct GuidePreview: View {
    @ObservedObject var sel: GuideSelection
    let channels: [Channel]
    let cc: String
    let groupLabel: String
    let play: (Int) -> Void
    @EnvironmentObject var user: UserStore

    private var channel: Channel? { channels.indices.contains(sel.current) ? channels[sel.current] : nil }
    private func item(_ c: Channel) -> MediaItem {
        MediaItem(kind: .live, id: c.id, name: c.name, img: c.icon, sub: Countries.name(cc) + " · " + groupLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.logoBg, Color(red: 0x12 / 255, green: 0x13 / 255, blue: 0x18 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let c = channel {
                    LogoBox(name: c.name, icon: c.icon, w: 250, h: 150, radius: 14, font: 34)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    LivePill().padding(20)
                }
            }
            .frame(width: 576, height: 324)
            if let c = channel {
                Text(c.name).font(.ui(40, .bold)).lineLimit(1).padding(.horizontal, 30).padding(.top, 32)
                Text("\(Countries.name(cc))  ·  \(groupLabel)  ·  Channel \(sel.current + 1)").font(.ui(22)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).padding(.horizontal, 30).padding(.top, 10)
                HStack(spacing: 14) {
                    Button { play(sel.current) } label: { Label("Watch", systemImage: "play.fill") }
                    Button { user.toggleFav(item(c), cc: cc) } label: {
                        user.isFav(c.id) ? Label("Favourite", systemImage: "star.fill") : Label("Favourite", systemImage: "star")
                    }
                    Button { user.toggle(item(c)) } label: {
                        user.inList(item(c)) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                    }
                }
                .buttonStyle(PillButtonStyle(height: 56, font: 21, hPad: 20))
                .padding(.horizontal, 30).padding(.top, 40)
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One channel line (.ch): number, logo, name, star when in My List.
struct ChannelRow: View {
    let n: Int
    let channel: Channel
    let fav: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        let _ = Metrics.shared.count("ChannelRow")
        HStack(spacing: 0) {
            Text("\(n)").font(.ui(20)).opacity(0.45).frame(width: 60, alignment: .leading)
            LogoBox(name: channel.name, icon: channel.icon, w: 86, h: 52)
            Text(channel.name).font(.ui(25, .medium)).lineLimit(1).padding(.leading, 22)
            Spacer(minLength: 12)
            if fav { Image(systemName: "star.fill").font(.ui(22)).foregroundStyle(Theme.gold) }
        }
        .padding(.leading, 18).padding(.trailing, 22)
        .frame(width: 652, height: 78)
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }
    struct Face: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .fontWeight(focused ? .bold : .medium)
                .foregroundStyle(focused ? Color.black : Color.white.opacity(0.86))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(focused ? Color.white : Color.clear))
                .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: focused ? 18 : 0, y: focused ? 14 : 0)
                .scaleEffect(focused ? 1.03 : 1)
                .zIndex(focused ? 2 : 0)
                .animation(Theme.ease, value: focused)
        }
    }
}

extension View {
    /// Runs when this view receives focus.
    func onMoveFocus(_ action: @escaping () -> Void) -> some View { modifier(FocusWatch(action: action)) }
}

private struct FocusWatch: ViewModifier {
    let action: () -> Void
    @FocusState private var f: Bool
    func body(content: Content) -> some View {
        content.focused($f).onChange(of: f) { _, on in if on { action() } }
    }
}
