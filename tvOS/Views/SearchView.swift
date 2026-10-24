import SwiftUI

/// Search: Apple's own search screen (`.searchable`): the system keyboard row, dictation and the iPhone typing prompt.
/// Results below it: Channels, Films, Series (chosen countries, languages and added lists), then channels of every
/// other country and films and series of every other language, each with its country or language badge.
struct SearchView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var q = ""
    @State private var results: [[MediaItem]] = Self.empty
    private static let empty: [[MediaItem]] = Array(repeating: [], count: 6)
    @State private var searching: Task<Void, Never>?
    @State private var loadingMore = false

    private static let rows: [(String, TileShape, CGFloat, CGFloat)] = [
        ("Channels", .logo, 220, 132), ("Films", .poster, 150, 225), ("Series", .poster, 150, 225),
        ("Channels · other countries", .logo, 220, 132), ("Films · other languages", .poster, 150, 225), ("Series · other languages", .poster, 150, 225)]
    private static let maxHits = 30

    var body: some View {
        let _ = Metrics.shared.count("SearchView")
        NavigationStack {
            GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    if q.trimmingCharacters(in: .whitespaces).isEmpty {
                        EmptyNote(text: "Type, dictate or use your iPhone. Results show here as you type.")
                    } else if results.allSatisfy(\.isEmpty) {
                        EmptyNote(text: catalog.indexState == .loading || loadingMore ? "Searching the whole catalogue…" : "Nothing found for “\(q)”")
                    }
                    ForEach(0..<Self.rows.count, id: \.self) { i in
                        if !results[i].isEmpty { row(i) }
                    }
                }
                .padding(.horizontal, 80).padding(.top, 20).padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // results scroll under the search field and keyboard: hide what is above them
            .mask(alignment: .top) { VStack(spacing: 0) { Color.clear.frame(height: g.safeAreaInsets.top); Color.black }.ignoresSafeArea() }
            }
        }
        .searchable(text: $q, prompt: "Channels, films, series")
        .onChange(of: q) { _, _ in run() }
        .padding(.top, 130)       // below the Nexus header and menu
        .background(Color.black)
        .onAppear {
            catalog.needIndex()
            Metrics.shared.mark("ready:search")
            if !nav.searchSeed.isEmpty { q = nav.searchSeed; nav.searchSeed = "" }
        }
        .onChange(of: catalog.indexState) { _, s in if s == .ready, !q.isEmpty { run() } }
    }

    private func row(_ i: Int) -> some View {
        let (title, shape, w, h) = Self.rows[i]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.ui(26, .semibold)).foregroundStyle(.white.opacity(0.9))
                Text("\(results[i].count)\(results[i].count >= Self.maxHits ? "+" : "")").font(.ui(26)).foregroundStyle(.white.opacity(0.45))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(Array(results[i].enumerated()), id: \.element.key) { j, it in
                        ResultTile(item: it, shape: shape, w: w, h: h) { open(it, row: i, index: j) }
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private func open(_ it: MediaItem, row: Int, index: Int) {
        if it.kind == .live { nav.play(it, list: results[row], index: index, subtitle: it.sub) } else { nav.open(it) }
    }

    /// Matches names that start with the text first, then a word start, then anywhere; shorter names first.
    private func run() {
        searching?.cancel()
        let needle = q.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { results = Self.empty; return }
        let chosen = settings.countries
        let groups: [(String, [XCategory])] = chosen.map { ($0, catalog.liveGroups($0)) }
        let live = catalog.liveIndex
        let films = catalog.index.films, series = catalog.index.series
        let maxHits = Self.maxHits
        let lists = settings.lists
        searching = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            // lists added in Settings (any category, any language): their items load once, then are cached
            var extra: [MediaItem] = []
            for l in lists { extra += await catalog.listItems(l) }
            if Task.isCancelled { return }
            // pass 1: chosen languages, channels and added lists, shown at once
            let main = await SearchEngine.match(needle, groups: groups, live: live, films: films, series: series, extra: extra,
                                        other: [], otherLive: [:], maxHits: maxHits)
            if Task.isCancelled { return }
            results = main
            Metrics.shared.mark("search.main \(main.map(\.count))")
            // pass 2: every channel of every other country and every film and series of every other language (names only),
            // loaded off the main thread the first time a query has 3+ letters
            guard needle.count >= 3 else { return }
            loadingMore = true
            await catalog.ensureLiveIndex()
            let other = await catalog.moreIndex()
            loadingMore = false
            if Task.isCancelled { return }
            let otherLive = catalog.liveCodes().filter { !chosen.contains($0.value) }
            let all = await SearchEngine.match(needle, groups: groups, live: catalog.liveIndex, films: films, series: series, extra: extra,
                                       other: other, otherLive: otherLive, maxHits: maxHits)
            if Task.isCancelled { return }
            results = all
            Metrics.shared.mark("search.all other=\(other.count) \(all.map(\.count))")
        }
    }

}

struct ResultTile: View {
    let item: MediaItem
    let shape: TileShape
    let w: CGFloat, h: CGFloat
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 14) {
            Button(action: action) { TileFace(item: item, shape: shape, w: w, h: h) }
                .buttonStyle(TileButtonStyle())
                .focused($focused)
            Text(item.name).font(.ui(20, .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                .frame(width: w + 80).opacity(focused ? 1 : 0)
        }
        .frame(width: w)
    }
}
