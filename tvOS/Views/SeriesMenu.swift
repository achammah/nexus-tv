import SwiftUI

/// What a long press on a series tile opens: the show, where it was left, and the row it sits in (Home only).
struct SeriesMenuRequest: Identifiable {
    let id = UUID()
    var series: MediaItem            // kind .series
    var rowId: String? = nil         // a Home row: Move and Hide row are offered
    var tileId: String? = nil
}

extension MediaItem {
    /// The series a tile stands for: a series tile itself, or an episode (Continue watching) through its series id. Nil for anything else.
    var seriesTile: MediaItem? {
        if kind == .series { return self }
        if kind == .episode, let sid = seriesId { return MediaItem(kind: .series, id: sid, name: seriesName ?? name, img: img) }
        return nil
    }
}

private extension View {
    /// Long press (hold Select) on a Button: runs `action`; a short click still activates the Button.
    func holdToOpen(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in action() })
    }
}

extension View {
    /// A series tile opens the series menu on a long press; every other tile keeps the system menu with `menu`.
    @ViewBuilder func tileMenu<M: View>(for item: MediaItem, nav: Nav, row: String? = nil, tile: String? = nil, @ViewBuilder menu: () -> M) -> some View {
        if let s = item.seriesTile { holdToOpen { nav.seriesMenu = SeriesMenuRequest(series: s, rowId: row, tileId: tile) } }
        else { contextMenu { menu() } }
    }
}

/// The long-press menu of a series: a header ("Show · S1 E3 at 10:34"), Resume, Open the show, Go to episode… (season
/// chips, then episode chips; OK plays that episode), My List, and on Home rows Move and Hide row.
struct SeriesMenuView: View {
    let req: SeriesMenuRequest
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var settings: Settings
    @State private var details: Details?
    @State private var picking = false
    @State private var season = ""
    @FocusState private var focus: String?

    private var last: ResumePoint? { user.lastEpisode(ofSeries: req.series.id) }
    private var epTag: String { last.flatMap { Self.tag($0.item) } ?? "" }          // "S1 E3"
    private var header: String {
        guard let l = last, let t = Self.tag(l.item) else { return req.series.name }
        return req.series.name + " · " + t + (l.posMs >= 1000 ? " at " + fmtTime(l.posMs) : "")
    }
    private var inList: Bool { user.inList(req.series) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(alignment: .leading, spacing: 4) {
                Text(header).font(.ui(22)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).padding(.horizontal, 18).padding(.bottom, 8)
                if let l = last, l.posMs >= 1000 {
                    row("Resume \(Self.tag(l.item).flatMap { $0.split(separator: " ").last.map(String.init) } ?? "")", "play.fill",
                        detail: l.durMs > 0 ? "\(fmtTime(l.posMs)) of \(fmtTime(l.durMs))" : fmtTime(l.posMs), id: "resume") { resume(l) }
                }
                row("Open the show", nil, detail: "seasons and episodes", id: "open") { nav.seriesMenu = nil; nav.open(req.series) }
                row("Go to episode…", nil, detail: nil, id: "goto") { withAnimation(.easeOut(duration: 0.15)) { picking.toggle() } }
                if picking { chips }
                row(inList ? "Remove from My List" : "Add to My List", nil, detail: nil, id: "list") { user.toggle(req.series); nav.seriesMenu = nil }
                if let rowId = req.rowId {
                    row("Move", nil, detail: nil, id: "move") { nav.seriesMenu = nil; nav.movingRow = rowId; nav.movingTile = req.tileId }
                    row("Hide row", nil, detail: nil, id: "hide") {
                        settings.hideRow(rowId); nav.seriesMenu = nil
                        user.show("Row hidden · Settings › Home rows shows it again")
                    }
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .focusSection()
        }
        .frame(width: 1920, height: 1080)
        .onExitCommand { if picking { picking = false; focus = "goto" } else { nav.seriesMenu = nil } }
        .task {
            details = PlayerDemo.on ? PlayerDemo.series() : await catalog.details(req.series)
            season = last.flatMap { Self.tagParts($0.item)?.season } ?? details?.seasons.first ?? ""
        }
        .onAppear { focus = last.map { $0.posMs >= 1000 ? "resume" : "open" } ?? "open" }
        .accessibilityIdentifier("seriesmenu")
    }

    private func row(_ title: String, _ icon: String?, detail: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon) }
                Text(title)
                Spacer(minLength: 12)
                if let detail { Text(detail).font(.ui(20)).opacity(0.6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChipButtonStyle(height: 62, font: 28))
        .accessibilityLabel(title)
        .focused($focus, equals: id)
    }

    /// Season chips, then the chips of the chosen season's episodes.
    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = details {
                let cols = [GridItem(.adaptive(minimum: 70), spacing: 8)]
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(d.seasons, id: \.self) { s in
                        Button { season = s } label: { Text("S\(s)").frame(minWidth: 40) }
                            .buttonStyle(ChipButtonStyle(selected: s == season, height: 46, radius: 23, font: 21, hPad: 14, idle: Color.white.opacity(0.08), onFill: Color.white.opacity(0.24)))
                            .accessibilityLabel("Season \(s)")
                            .focused($focus, equals: "s:" + s)
                    }
                }
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(d.episodes[season] ?? []) { e in
                        Button { play(e, season: season, in: d) } label: { Text("E\(e.num)").frame(minWidth: 40) }
                            .buttonStyle(ChipButtonStyle(height: 46, radius: 23, font: 21, hPad: 14, idle: Color.white.opacity(0.08)))
                            .accessibilityLabel("Episode \(e.num)")
                            .focused($focus, equals: "e:" + e.id)
                    }
                }
            } else {
                Text("Loading…").font(.ui(20)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onAppear {
            guard let d = details else { return }
            let eps = d.episodes[season] ?? []
            // opens on the episode that was left (when it is in this season), else the first
            if let l = last, eps.contains(where: { $0.id == l.item.id }) { focus = "e:" + l.item.id } else if let e = eps.first { focus = "e:" + e.id }
        }
    }

    // MARK: playing

    private func epItem(_ e: Episode, _ s: String) -> MediaItem {
        MediaItem(kind: .episode, id: e.id, name: "\(req.series.name) · S\(s) E\(e.num)", img: req.series.img, ext: e.ext, sub: e.title,
                  seriesId: req.series.id, seriesName: req.series.name)
    }

    private func after(_ id: String, in d: Details) -> [MediaItem] {
        let all = d.seasons.flatMap { s in (d.episodes[s] ?? []).map { (s, $0) } }
        guard let i = all.firstIndex(where: { $0.1.id == id }) else { return [] }
        return all.dropFirst(i + 1).map { epItem($0.1, $0.0) }
    }

    private func play(_ e: Episode, season s: String, in d: Details) {
        let it = epItem(e, s)
        nav.seriesMenu = nil
        nav.play(it, startMs: user.resumePoint(it)?.posMs ?? 0, subtitle: e.title, next: after(e.id, in: d), picture: d.backdrop.isEmpty ? req.series.img : d.backdrop)
    }

    private func resume(_ r: ResumePoint) {
        let next: [MediaItem] = details.map { after(r.item.id, in: $0) } ?? []
        nav.seriesMenu = nil
        nav.play(r.item, startMs: r.posMs, subtitle: r.item.sub, next: next, picture: details?.backdrop ?? req.series.img)
    }

    /// "S1 E3" from an episode item's name ("House Of Guinness · S1 E3").
    static func tag(_ it: MediaItem) -> String? {
        it.name.range(of: "S\\d+ E\\d+$", options: .regularExpression).map { String(it.name[$0]) }
    }
    static func tagParts(_ it: MediaItem) -> (season: String, ep: String)? {
        guard let t = tag(it) else { return nil }
        let p = t.split(separator: " ").map { String($0.dropFirst()) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }
}
