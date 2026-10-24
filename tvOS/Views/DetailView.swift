import SwiftUI

/// One film or series: backdrop, title, facts, plot, Play / My List, then seasons and episodes for a series.
struct DetailView: View {
    let item: MediaItem
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: Nav
    @State private var info: Details?
    @State private var failed = false
    @State private var season = ""
    @FocusState private var playFocused: Bool

    private var title: String { Clean.display(item.name.isEmpty ? (info?.name ?? "") : item.name) }
    private var episodes: [Episode] { info?.episodes[season] ?? [] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let b = info?.backdrop, !b.isEmpty {
                RemoteImage(url: Img.url(b, .backdrop), maxPixel: 1920, mode: .fill) { Color.black }
                    .frame(width: 1920, height: 1080).clipped().transition(.opacity)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.92), location: 0), .init(color: .black.opacity(0.6), location: 0.45),
                                   .init(color: .black.opacity(0.15), location: 0.8)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom).frame(height: 540).offset(y: 540)

            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.ui(72, .bold)).tracking(-1).lineLimit(2).frame(width: 1100, alignment: .leading).padding(.bottom, 18)
                Facts(parts: (info?.facts ?? []) + (user.hasSubs(item) ? ["CC"] : [])).frame(height: 32).padding(.bottom, 18)
                Text(info?.plot ?? "").font(.ui(24)).lineSpacing(10).foregroundStyle(.white.opacity(0.75)).lineLimit(3)
                    .frame(width: 900, alignment: .leading).padding(.bottom, 34)
                HStack(spacing: 16) {
                    Button(action: play) { Label(playLabel, systemImage: "play.fill") }
                        .focused($playFocused)
                    Button { user.toggle(saved) } label: {
                        user.inList(saved) ? Label("In My List", systemImage: "checkmark") : Label("My List", systemImage: "plus")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .focusSection()
                if item.kind == .series, let info, info.seasons.isEmpty {
                    Text("No episodes available for this series yet").font(.ui(22)).foregroundStyle(.white.opacity(0.5)).padding(.top, 24)
                }
                if failed { Text("Could not load details").font(.ui(22)).foregroundStyle(.white.opacity(0.5)).padding(.top, 24) }
            }
            .padding(.leading, Theme.x0).padding(.top, 170)

            if item.kind == .series, let info, !info.seasons.isEmpty {
                VStack(alignment: .leading, spacing: 30) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(info.seasons, id: \.self) { s in
                                Button { season = s } label: { Text("Season \(s)") }
                                    .buttonStyle(ChipButtonStyle(selected: s == season, height: 46, radius: 23, font: 21, hPad: 20,
                                                                 idle: Color.white.opacity(0.08), onFill: Color.white.opacity(0.22), dim: 0.7))
                                    .onMoveFocus { season = s }
                            }
                        }
                        .padding(.horizontal, Theme.x0).padding(.vertical, 8)
                    }
                    .frame(height: 62)
                    .focusSection()
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 26) {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                                Button { playEpisode(e) } label: { EpisodeCard(ep: e, index: i, fallback: item.img, progress: user.resumePoint(epItem(e))?.fraction) }
                                    .buttonStyle(TileButtonStyle(scale: 1.07, lift: 6))
                            }
                        }
                        .padding(.horizontal, Theme.x0).padding(.vertical, 14)
                    }
                    .frame(height: 242)
                    .scrollClipDisabled()
                    .focusSection()
                }
                .frame(width: 1920, height: 1040, alignment: .bottomLeading)
            } else if info == nil && !failed {
                Spinner().padding(.leading, 936).padding(.top, 700)
            }
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: info?.backdrop)
        .task {
            playFocused = true
            let d = await catalog.details(item)
            if let d { info = d; season = d.seasons.first ?? "" } else { failed = true }
        }
    }

    private var saved: MediaItem { MediaItem(kind: item.kind, id: item.id, name: title, img: item.img.isEmpty ? (info?.poster ?? "") : item.img, ext: info?.ext ?? item.ext) }

    private var playLabel: String {
        if item.kind == .film, let r = user.resumePoint(MediaItem(kind: .film, id: item.id, name: "")), r.posMs >= 10_000 { return "Resume " + fmtTime(r.posMs) }
        if item.kind == .series, let r = user.lastEpisode(ofSeries: item.id) { return "Resume " + (r.item.name.components(separatedBy: " · ").last ?? "") }
        return "Play"
    }

    private var poster: String { item.img.isEmpty ? (info?.poster ?? "") : item.img }

    private func epItem(_ e: Episode, _ s: String? = nil) -> MediaItem {
        MediaItem(kind: .episode, id: e.id, name: "\(title) · S\(s ?? season) E\(e.num)", img: poster, ext: e.ext, sub: e.title, seriesId: item.id, seriesName: title)
    }

    /// Every episode after this one, through the following seasons.
    private func episodesAfter(_ e: Episode) -> [MediaItem] {
        guard let info else { return [] }
        let all = info.seasons.flatMap { s in (info.episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == e.id }) else { return [] }
        return all.dropFirst(i + 1).map { epItem($0.1, $0.0) }
    }

    private func play() {
        if item.kind == .film {
            var f = saved
            if f.ext.isEmpty { f.ext = "mp4" }
            nav.play(f, startMs: user.resumePoint(f)?.posMs ?? 0, subtitle: (info?.facts ?? []).joined(separator: " · "), picture: info?.backdrop ?? poster)
            return
        }
        if let r = user.lastEpisode(ofSeries: item.id) {
            let ep = info?.episodes.values.flatMap { $0 }.first { $0.id == r.item.id }
            nav.play(r.item, startMs: r.posMs, subtitle: r.item.sub, next: ep.map(episodesAfter) ?? [], picture: info?.backdrop ?? poster)
            return
        }
        if let first = info?.seasons.first, let e = info?.episodes[first]?.first { season = first; playEpisode(e) }
    }

    private func playEpisode(_ e: Episode) {
        let it = epItem(e)
        nav.play(it, startMs: user.resumePoint(it)?.posMs ?? 0, subtitle: e.title, next: episodesAfter(e), picture: info?.backdrop ?? poster)
    }
}

struct EpisodeCard: View {
    let ep: Episode
    let index: Int
    let fallback: String
    var progress: Double? = nil
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.tile
            RemoteImage(url: Img.url(ep.still.isEmpty ? fallback : ep.still, .still), maxPixel: 800, mode: .fill) { Theme.tile }
                .frame(width: 380, height: 214).clipped()
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 90)
            Text("\(ep.num > 0 ? ep.num : index + 1). \(ep.title.isEmpty ? "Episode \(index + 1)" : ep.title)")
                .font(.ui(21, .semibold)).lineLimit(1).shadow(color: .black.opacity(0.9), radius: 3, y: 2)
                .padding(.horizontal, 16).padding(.bottom, progress == nil ? 14 : 20)
            if let p = progress { Rectangle().fill(Theme.red).frame(width: 380 * p, height: 6) }
        }
        .frame(width: 380, height: 214)
    }
}
