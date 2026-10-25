import SwiftUI

/// Films / Series: categories on the left, poster grid on the right.
struct LibraryView: View {
    let kind: ItemKind
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var catId = ""
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var pending: Task<Void, Never>?

    private var cats: [XCategory] { catalog.libraryCategories(kind, languages: settings.languages) }
    private func label(_ c: XCategory) -> String {
        let t = Clean.tag(c.name) ?? ""
        return (t.isEmpty ? "" : t + " · ") + Clean.titleCase(Clean.category(c.name))
    }

    var body: some View {
        let _ = Metrics.shared.count("LibraryView")
        ZStack(alignment: .topLeading) {
            Color.black
            HStack(alignment: .top, spacing: 36) {
            categories.frame(width: 400, height: 840).background(Glass())
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(cats.first { $0.id == catId }.map(label) ?? "").font(.ui(26, .semibold)).foregroundStyle(.white.opacity(0.9))
                    if !items.isEmpty { Text("\(items.count) titles").font(.ui(26)).foregroundStyle(.white.opacity(0.45)) }
                }
                .frame(height: 40, alignment: .leading)
                if loading {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(180), spacing: 30), count: 6), alignment: .leading, spacing: 56) {
                        ForEach(0..<12, id: \.self) { _ in Skeleton().frame(width: 180, height: 270) }
                    }
                    .padding(.top, 34).padding(.horizontal, 14)
                } else if items.isEmpty && !catId.isEmpty {
                    EmptyNote(text: "Nothing in this category").padding(.top, 40)
                } else {
                    PosterGrid(items: items, columns: 6, w: 180, h: 270, gx: 30, gy: 26, topInset: 34) { nav.open($0) }
                }
            }
            .frame(width: 1330, height: 914, alignment: .topLeading)
            .padding(.top, 16)
            }
            .padding(.leading, 112).padding(.top, 150)
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .onAppear { catalog.needIndex(); if catId.isEmpty, let f = cats.first { select(f.id) } }
        .onChange(of: cats.map(\.id)) { _, ids in if !ids.contains(catId), let f = ids.first { select(f) } }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: kind == .film ? "Film categories" : "Series categories").padding(.leading, 32).padding(.top, 30).padding(.bottom, 16)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(cats) { c in
                        Button { select(c.id) } label: {
                            HStack {
                                Text(label(c)).lineLimit(1)
                                Spacer(minLength: 12)
                                if let n = catalog.counts[c.id] { Text("\(n)").font(.ui(19)).opacity(0.55) }
                            }
                            .frame(width: 328)
                        }
                        .buttonStyle(ChipButtonStyle(selected: c.id == catId))
                        .onMoveFocus { pending?.cancel(); pending = Task { try? await Task.sleep(nanoseconds: 350_000_000); if !Task.isCancelled { select(c.id) } } }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 4)
            }
            .frame(height: 760)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }

    private func select(_ id: String) {
        guard id != catId else { return }
        catId = id; loading = true; items = []
        Task {
            let list = await catalog.items(kind, id)
            if catId == id { items = list; loading = false; Metrics.shared.mark("ready:" + (kind == .film ? "films" : "series")) }
        }
    }
}

/// Poster grid with captions under each tile (focused caption in white).
struct PosterGrid: View {
    let items: [MediaItem]
    let columns: Int
    let w: CGFloat, h: CGFloat, gx: CGFloat, gy: CGFloat
    var topInset: CGFloat = 20
    var progress: [String: Double] = [:]
    /// Focus this tile when `focusTick` changes (a page coming back on top).
    var focusKey: String? = nil
    var focusTick = 0
    let action: (MediaItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: gx, alignment: .top), count: columns), alignment: .leading, spacing: gy) {
                ForEach(items, id: \.key) { it in
                    GridTile(item: it, w: w, h: h, progress: progress[it.key], focusMe: it.key == focusKey, focusTick: focusTick) { action(it) }
                }
            }
            .padding(.top, topInset).padding(.bottom, 80).padding(.horizontal, 14)
        }
        // clipped: the grid must never scroll over the header; the insets leave room for the focus lift
        .focusSection()
    }
}

struct GridTile: View {
    let item: MediaItem
    let w: CGFloat, h: CGFloat
    var progress: Double? = nil
    var focusMe = false
    var focusTick = 0
    let action: () -> Void
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: Nav
    @FocusState private var focused: Bool
    var body: some View {
        let _ = Metrics.shared.count("GridTile")
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) { TileFace(item: item, shape: item.kind == .live ? .logo : .poster, w: w, h: item.kind == .live ? w * 0.6 : h, progress: progress) }
                .buttonStyle(TileButtonStyle())
                .focused($focused)
                .onChange(of: focusTick) { _, _ in if focusMe { focused = true } }
                .tileMenu(for: item, nav: nav) {
                    Button(action: action) { Label(item.kind == .live ? "Watch" : "Open", systemImage: "play.fill") }
                    Button { user.toggle(item) } label: {
                        user.inList(item) ? Label("Remove from My List", systemImage: "minus.circle") : Label("Add to My List", systemImage: "plus")
                    }
                }
                .frame(height: h, alignment: .top)
            Text(item.name).font(.ui(19)).foregroundStyle(focused ? .white : .white.opacity(0.55)).lineLimit(1).frame(width: w, alignment: .leading)
        }
    }
}

/// My List: everything saved, in an 8-column grid.
struct MyListView: View {
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: Nav
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("My List").font(.ui(26, .semibold)).foregroundStyle(.white.opacity(0.9))
                    if !user.myList.isEmpty { Text("\(user.myList.count) titles").font(.ui(26)).foregroundStyle(.white.opacity(0.45)) }
                }
                if user.myList.isEmpty {
                    VStack(spacing: 26) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(red: 0.83, green: 0.58, blue: 0.90).opacity(0.22), Color(red: 0.68, green: 0.86, blue: 0.56).opacity(0.10)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 170, height: 170)
                            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5).frame(width: 170, height: 170)
                            Image(systemName: "bookmark").font(.system(size: 64, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        }
                        Text("Your list is empty").font(.ui(44, .bold))
                        Text("Choose + My List on any channel, film or series to save it here.").font(.ui(26)).foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 150)
                    .accessibilityIdentifier("mylist-empty")
                } else {
                    PosterGrid(items: user.myList, columns: 8, w: 180, h: 270, gx: 30, gy: 26, topInset: 34) { it in
                        if it.kind == .live { nav.play(it, list: [it], subtitle: "My List") } else { nav.open(it) }
                    }
                }
            }
            .frame(width: 1720, height: 914, alignment: .topLeading)
            .padding(.leading, 126).padding(.top, 166)
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
    }
}
