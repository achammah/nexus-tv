import SwiftUI

/// Film or series page: blurred poster behind, the poster, title and facts, Play / Resume and My List, the plot,
/// then for a series the seasons and every episode with its own progress bar from the resume store.
struct DetailPage: View {
    let item: MediaItem
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: MacNav
    @State private var d: Details?
    @State private var season = ""

    private var title: String { Clean.display(item.name.isEmpty ? (d?.name ?? "") : item.name) }
    private var poster: String { d.map { $0.poster.isEmpty ? item.img : $0.poster } ?? item.img }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                if item.kind == .series, let d { episodes(d) }
            }
        }
        .task {
            d = await catalog.details(item)
            if let d, season.isEmpty {
                let last = user.lastEpisode(ofSeries: item.id)
                season = d.seasons.first { s in (d.episodes[s] ?? []).contains { $0.id == last?.item.id } } ?? d.seasons.first ?? ""
            }
        }
    }

    private var head: some View {
        ZStack(alignment: .topLeading) {
            MacImage(url: Img.url(poster)) { Color.black }
                .frame(maxWidth: .infinity).frame(height: 430).clipped()
                .blur(radius: 40).brightness(-0.35).saturation(1.2)
            LinearGradient(colors: [MacTheme.window.opacity(0), MacTheme.window], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
            HStack(alignment: .top, spacing: 32) {
                MacImage(url: Img.url(poster)) { MacTheme.tile }
                    .frame(width: 232, height: 348).clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.6), radius: 25, y: 18)
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.system(size: 38, weight: .heavy)).tracking(-0.8).lineLimit(2)
                    Text(((d?.facts ?? []) + [item.kind == .film ? "Film" : "Series"]).joined(separator: "  ·  ")).font(.system(size: 13)).foregroundStyle(MacTheme.soft)
                    HStack(spacing: 10) {
                        if let r = resumeTarget {
                            Button { play(r.item, at: r.posMs) } label: { Label(r.posMs > 0 ? "Resume" : "Play", systemImage: "play.fill") }
                                .buttonStyle(MacPill(primary: true)).accessibilityIdentifier("play")
                        }
                        Button { user.toggle(item) } label: {
                            user.inList(item) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                        }
                        .buttonStyle(MacPill())
                    }
                    .padding(.vertical, 12)
                    if let p = d?.plot, !p.isEmpty {
                        Text(p).font(.system(size: 13.5)).lineSpacing(3).foregroundStyle(MacTheme.soft).frame(maxWidth: 640, alignment: .leading)
                    } else if d == nil { Shimmer().frame(width: 520, height: 80) }
                    if item.kind == .film, let r = user.resumePoint(item), r.fraction > 0.01 {
                        HStack(spacing: 10) { ProgressLine(fraction: r.fraction).frame(width: 220); Text(remaining(r)).font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
                            .padding(.top, 6)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 32).padding(.top, 30)
        }
        .frame(height: 430)
    }

    /// What Play starts: a film's resume point, or for a series the episode watched last (or the first one).
    private var resumeTarget: (item: MediaItem, posMs: Int)? {
        if item.kind == .film { return (item, user.resumePoint(item)?.posMs ?? 0) }
        guard let d else { return nil }
        if let last = user.lastEpisode(ofSeries: item.id), all(d).contains(where: { $0.key == last.item.key }) { return (last.item, last.posMs) }
        return all(d).first.map { ($0, 0) }
    }

    private func episodes(_ d: Details) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if d.seasons.count > 1 {
                Picker("Season", selection: $season) { ForEach(d.seasons, id: \.self) { Text("Season " + $0).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 520).labelsHidden()
            } else if let s = d.seasons.first { RowTitle(title: "Season " + s) }
            ForEach(d.episodes[season] ?? [], id: \.id) { e in
                let ep = episodeItem(e, season: season, d: d)
                let r = user.resumePoint(ep)
                Button { play(ep, at: r?.posMs ?? 0) } label: {
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomLeading) {
                            MacImage(url: Img.url(e.still.isEmpty ? poster : e.still, .still)) { MacTheme.tile }
                                .frame(width: 192, height: 108).clipped()
                            if let f = r?.fraction, f > 0.01 { ProgressLine(fraction: f).padding(8) }
                        }
                        .frame(width: 192, height: 108).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(e.num). " + (e.title.isEmpty ? "Episode \(e.num)" : e.title)).font(.system(size: 14, weight: .semibold))
                            if e.durationSecs > 0 { Text("\(e.durationSecs / 60) min").font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
                            if let r, r.fraction > 0.01 { Text(remaining(r)).font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
                        }
                        Spacer()
                        Image(systemName: "play.circle").font(.system(size: 22)).foregroundStyle(MacTheme.dim)
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("episode:\(season):\(e.num)")
                .accessibilityLabel("Episode \(e.num)" + (r.map { ", watched \(Int($0.fraction * 100)) percent" } ?? ""))
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 30)
    }

    private func remaining(_ r: ResumePoint) -> String {
        let left = max(0, r.durMs - r.posMs) / 60_000
        return left > 0 ? "\(left) min left" : "Watched"
    }
    private func episodeItem(_ e: Episode, season s: String, d: Details) -> MediaItem {
        MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s) E\(e.num)", img: e.still.isEmpty ? poster : e.still, ext: e.ext, sub: e.title,
                  seriesId: item.id, seriesName: title)
    }
    private func all(_ d: Details) -> [MediaItem] { d.seasons.flatMap { s in (d.episodes[s] ?? []).map { episodeItem($0, season: s, d: d) } } }

    private func play(_ it: MediaItem, at ms: Int) {
        var next: [MediaItem] = []
        if it.kind == .episode, let d, let i = all(d).firstIndex(where: { $0.key == it.key }) { next = Array(all(d).dropFirst(i + 1)) }
        Player(nav: nav).play(it, startMs: ms, next: next, picture: poster)
    }
}
