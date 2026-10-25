import SwiftUI
import AppKit
import VLCKit

/// The parts of the redesigned Mac player for films and episodes (docs/DESIGN.md "Player (2026-10-25)"):
/// the labelled bar, the Audio and Subtitles popups, the Episodes strip, the compact end card and the "Still watching?" toast.
/// Live channels keep the bar in MacPlayerWindow.swift.

enum PlayerPopup { case audio, subtitles }

private let barFill = Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255)
private let panelFill = Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255)

/// A round flag, or a grey circle when the language has none.
struct FlagDot: View {
    let asset: String?
    var size: CGFloat = 18
    var body: some View {
        Group {
            if let asset, NSImage(named: asset) != nil { Image(asset).resizable().scaledToFill() } else { Circle().fill(Color.white.opacity(0.22)) }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

// MARK: - The bar

/// Bottom of the player for a film or an episode: the bar, and above it the popup or the episode strip when open.
struct VODLayer: View {
    @ObservedObject var model: MacPlayerModel
    @ObservedObject var vlc: VLCController
    @Binding var dragMs: Int?
    let togglePip: () -> Void
    let toggleFull: () -> Void
    @State private var hoverButton = false
    @State private var hoverStrip = false
    private static let stripHeight: CGFloat = 176

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.stripOpen {
                EpisodeStrip(model: model, vlc: vlc, hover: $hoverStrip)
                    .frame(height: Self.stripHeight).padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onChange(of: hoverStrip) { _, _ in scheduleClose() }
            }
            VStack(spacing: 8) {
                if let p = model.popup {
                    HStack(spacing: 0) {
                        Spacer().frame(width: p == .audio ? 126 : 262)
                        TrackPopup(model: model, vlc: vlc, kind: p)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 760)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                bar
            }
            .padding(.bottom, model.stripOpen ? 22 + Self.stripHeight : 22)
        }
        .animation(.easeOut(duration: 0.22), value: model.stripOpen)
        .animation(.easeOut(duration: 0.14), value: model.popup)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func scheduleClose() {
        guard !hoverButton, !hoverStrip, !model.stripPinned else { return }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !hoverButton && !hoverStrip && !model.stripPinned { model.closeStrip() }
        }
    }

    private var bar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                round("gobackward.10", "Back 10 seconds", size: 32, glyph: 15) { model.seek(by: -10_000) }
                round(vlc.paused ? "play.fill" : "pause.fill", vlc.paused ? "Play" : "Pause", size: 40, glyph: 16, filled: true) { vlc.toggle() }
                    .accessibilityIdentifier("play-pause")
                round("goforward.10", "Forward 10 seconds", size: 32, glyph: 15) { model.seek(by: 10_000) }
                pill("speaker.wave.2.fill", "Audio", audioValue, active: model.popup == .audio, id: "audio-menu") { toggle(.audio) }
                pill("captions.bubble", "Subtitles", subtitleValue, active: model.popup == .subtitles, id: "cc-menu") { toggle(.subtitles) }
                Spacer(minLength: 0)
                if model.creditsReached, !model.next.isEmpty {
                    Button { model.playNext() } label: {
                        HStack(spacing: 6) { Image(systemName: "forward.end.fill").font(.system(size: 11)); Text("Next episode").font(.system(size: 13, weight: .semibold)) }
                            .padding(.horizontal, 12).frame(height: 34).foregroundStyle(.black)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain).help(model.next.first.map { $0.name + ($0.sub.isEmpty ? "" : " · " + $0.sub) } ?? "")
                    .accessibilityLabel("Next episode").accessibilityIdentifier("next-episode")
                }
                if let p = model.place {
                    pill("list.bullet", "Episodes", "\(p.n) of \(p.of)", active: model.stripOpen, id: "episodes-button", hover: { h in
                        hoverButton = h
                        if h { model.openStrip() } else { scheduleClose() }
                    }) {
                        if model.stripOpen && model.stripPinned { model.closeStrip() } else { model.openStrip(); model.stripPinned = true }
                    }
                }
            }
            timeline
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 12)
        .frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .background(RoundedRectangle(cornerRadius: 14).fill(barFill.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain).accessibilityIdentifier("hud")
    }

    private func toggle(_ p: PlayerPopup) { model.popup = model.popup == p ? nil : p; if model.popup != nil { model.closeStrip() } }

    private var audioValue: String {
        let list = vlc.audioTracks
        let labels = MacTrackLabel.make(tracks: vlc.trackInputs(audio: true, list: list))
        return labels.first { $0.id == vlc.audioIndex }?.text ?? (list.isEmpty ? "none" : "")
    }
    private var subtitleValue: String {
        if model.onlineTrack != nil && vlc.subtitleIndex == model.onlineTrack,
           let r = model.online.first(where: { $0.fileId == model.onlineActive }) { return OpenSubtitles.languageName(r.lang) }
        let embedded = vlc.subtitleTracks.filter { $0.0 != model.onlineTrack }
        let labels = MacTrackLabel.make(tracks: vlc.trackInputs(audio: false, list: embedded))
        return labels.first { $0.id == vlc.subtitleIndex }?.text ?? "Off"
    }

    private func round(_ name: String, _ label: String, size: CGFloat, glyph: CGFloat, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: glyph, weight: .semibold)).frame(width: size, height: size)
                .foregroundStyle(filled ? Color.black : Color.white)
                .background(Circle().fill(filled ? Color.white : Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func pill(_ icon: String, _ title: String, _ value: String?, active: Bool, id: String, hover: ((Bool) -> Void)? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 13, weight: .semibold))
                if let value, !value.isEmpty {
                    Text(value).font(.system(size: 12)).opacity(0.65).lineLimit(1).truncationMode(.tail).frame(maxWidth: 86, alignment: .leading)
                }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .foregroundStyle(active ? Color.black : Color.white)
            .background(Capsule().fill(active ? Color.white : Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover?($0) }
        .accessibilityLabel(title + (value.map { " " + $0 } ?? "")).accessibilityIdentifier(id)
    }

    private var timeline: some View {
        let shown = dragMs ?? vlc.timeMs
        return HStack(spacing: 12) {
            Text(PlayerFormat.clock(shown / 1000)).font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.soft)
            GeometryReader { g in
                let f = vlc.lengthMs > 0 ? CGFloat(min(1, Double(shown) / Double(vlc.lengthMs))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: g.size.width * f, height: 4)
                    Circle().fill(Color.white).frame(width: 13, height: 13).offset(x: g.size.width * f - 6.5)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in dragMs = Int(Double(max(0, min(g.size.width, v.location.x)) / g.size.width) * Double(vlc.lengthMs)) }
                    .onEnded { _ in if let d = dragMs { model.seek(toMs: d) }; dragMs = nil })
            }
            .frame(height: 16)
            .accessibilityElement().accessibilityLabel("Timeline").accessibilityValue(PlayerFormat.clock(shown / 1000)).accessibilityIdentifier("timeline")
            Text(vlc.lengthMs > 0 ? "−" + PlayerFormat.clock(max(0, vlc.lengthMs - shown) / 1000) : "").font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.soft)
            smallIcon("pip.enter", "Picture in picture", togglePip)
            smallIcon("arrow.up.left.and.arrow.down.right", "Full screen", toggleFull)
        }
    }
    private func smallIcon(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 14, weight: .medium)).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.white).help(label).accessibilityLabel(label)
    }
}

// MARK: - Audio and Subtitles popups (rule 2)

struct TrackPopup: View {
    @ObservedObject var model: MacPlayerModel
    @ObservedObject var vlc: VLCController
    let kind: PlayerPopup
    @ObservedObject private var osub = OpenSubtitles.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kind == .audio ? "Audio" : "Subtitles").font(.system(size: 15, weight: .bold)).padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            ScrollView { VStack(alignment: .leading, spacing: 2) { kind == .audio ? AnyView(audio) : AnyView(subtitles) } }
                .frame(maxHeight: 330).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8).frame(width: kind == .audio ? 300 : 340)
        .background(RoundedRectangle(cornerRadius: 14).fill(panelFill.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain).accessibilityIdentifier(kind == .audio ? "audio-popup" : "subtitles-popup")
    }

    private var audio: some View {
        let list = vlc.audioTracks
        let labels = MacTrackLabel.make(tracks: vlc.trackInputs(audio: true, list: list))
        return VStack(alignment: .leading, spacing: 2) {
            if list.count < 2 { Text("Only one audio track").font(.system(size: 12)).foregroundStyle(MacTheme.dim).padding(.horizontal, 10).padding(.vertical, 4) }
            ForEach(labels) { l in
                row(l.text, l.detail, flag: l.flag, showFlag: true, selected: l.id == vlc.audioIndex, id: "audio:\(l.id)") {
                    if let t = list.first(where: { $0.0 == l.id }) { model.choose(audio: t) }
                    model.popup = nil
                }
            }
        }
    }

    private var subtitles: some View {
        let embedded = vlc.subtitleTracks.filter { $0.0 != model.onlineTrack && $0.0 >= 0 }
        let labels = MacTrackLabel.make(tracks: vlc.trackInputs(audio: false, list: embedded))
        let current = vlc.subtitleIndex
        let onlineOn = model.onlineTrack != nil && current == model.onlineTrack
        return VStack(alignment: .leading, spacing: 2) {
            row("Off", "", flag: nil, showFlag: false, selected: current < 0, id: "sub:off") {
                if let off = vlc.subtitleTracks.first(where: { $0.0 < 0 }) { model.choose(subtitle: off) }
                model.popup = nil
            }
            ForEach(labels) { l in
                row(l.text, l.detail, flag: l.flag, showFlag: true, selected: l.id == current && !onlineOn, id: "sub:\(l.id)") {
                    if let t = embedded.first(where: { $0.0 == l.id }) { model.choose(subtitle: t) }
                    model.popup = nil
                }
            }
            if embedded.isEmpty { Text("No subtitles in this file").font(.system(size: 12)).foregroundStyle(MacTheme.dim).padding(.horizontal, 10).padding(.vertical, 4) }
            if osub.ready {
                header("ONLINE · OPENSUBTITLES")
                if model.onlineState == "loading" || model.onlineState.isEmpty { note("Searching…") }
                else if model.onlineState != "done" { note(model.onlineState) }
                ForEach(model.online) { r in
                    let lang = OpenSubtitles.languageName(r.lang)
                    row(lang + MacPlayerModel.releaseHint(r.release), r.exact ? "exact file" : (r.hearingImpaired ? "hearing impaired" : ""),
                        flag: LanguageFlag.asset(lang), showFlag: true, selected: onlineOn && model.onlineActive == r.fileId, id: "online:\(r.fileId)") {
                        Task { await model.pickOnline(r, remember: true) }
                        model.popup = nil
                    }
                }
                header("TIMING" + (onlineOn ? "  " + String(format: "%+.1f", Double(vlc.subtitleDelayMs) / 1000) + " s" : ""))
                HStack(spacing: 6) {
                    chip("Earlier −0.5 s", on: false, enabled: onlineOn) { model.shiftDelay(-500) }
                    chip("Auto", on: model.manualShiftMs == 0, enabled: onlineOn) { model.autoTiming() }
                    chip("Later +0.5 s", on: false, enabled: onlineOn) { model.shiftDelay(500) }
                }
                .padding(.horizontal, 6).padding(.bottom, 4)
            }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(MacTheme.dim).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
    }
    private func note(_ t: String) -> some View { Text(t).font(.system(size: 12)).foregroundStyle(MacTheme.dim).padding(.horizontal, 10).padding(.vertical, 4) }

    private func chip(_ t: String, on: Bool, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 28)
                .foregroundStyle(on ? Color.black : Color.white)
                .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }

    private func row(_ text: String, _ detail: String, flag: String?, showFlag: Bool, selected: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showFlag { FlagDot(asset: flag, size: 18) }
                Text(text).font(.system(size: 14)).lineLimit(1)
                Spacer(minLength: 8)
                if !detail.isEmpty { Text(detail).font(.system(size: 12)).opacity(0.6).lineLimit(1) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityLabel(text)
    }
}

// MARK: - The Episodes strip (rule 3)

struct EpisodeStrip: View {
    @ObservedObject var model: MacPlayerModel
    @ObservedObject var vlc: VLCController
    @Binding var hover: Bool
    @EnvironmentObject var user: UserStore
    @State private var wheel: CGFloat = 0
    @State private var monitor: Any?
    private let cardW: CGFloat = 200, gap: CGFloat = 12, pad: CGFloat = 24

    var body: some View {
        let cards = model.stripCards
        return GeometryReader { g in
            let total = CGFloat(cards.count) * (cardW + gap) - gap
            HStack(spacing: gap) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, c in card(i, c) }
            }
            .offset(x: offset(width: g.size.width, total: total))
            .animation(.easeOut(duration: 0.2), value: model.stripSel)
            .animation(.easeOut(duration: 0.12), value: wheel)
            .frame(width: g.size.width, alignment: .leading)
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onChange(of: model.stripSel) { _, _ in wheel = 0 }
        .onAppear {
            // the mouse wheel scrolls the strip while the pointer is on it
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                guard hover else { return e }
                let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
                wheel += e.hasPreciseScrollingDeltas ? d : d * 14
                let w = NSApp.keyWindow?.contentView?.bounds.width ?? 1200
                let total = CGFloat(model.stripCards.count) * (cardW + gap) - gap
                let centred = w / 2 - (CGFloat(model.stripSel) * (cardW + gap) + cardW / 2)
                wheel = min(max(wheel, (w - total - pad) - centred), pad - centred)
                return nil
            }
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
        .accessibilityElement(children: .contain).accessibilityIdentifier("episode-strip")
    }

    private func offset(width: CGFloat, total: CGFloat) -> CGFloat {
        if total + 2 * pad <= width { return (width - total) / 2 }
        let centred = width / 2 - (CGFloat(model.stripSel) * (cardW + gap) + cardW / 2)
        return min(pad, max(width - total - pad, centred + wheel))
    }

    @ViewBuilder private func card(_ i: Int, _ c: MacPlayerModel.StripCard) -> some View {
        let selected = i == model.stripSel
        switch c {
        case .episode(let e, let it): episodeCard(i, e, it, selected: selected)
        case .season(let s, let count, let next):
            Button { model.stripSel = i; model.stripPick(i) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next ? "Season \(s) ›" : "‹ Season \(s)").font(.system(size: 15, weight: .semibold))
                    Text("\(count) episodes").font(.system(size: 12)).foregroundStyle(MacTheme.dim)
                }
                .padding(14).frame(width: cardW, height: 112 + 46, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(panelFill.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: selected ? 3 : 0))
            }
            .buttonStyle(.plain).accessibilityIdentifier("season-card:\(s)").accessibilityLabel("Season \(s)")
        }
    }

    private func episodeCard(_ i: Int, _ e: Episode, _ it: MediaItem, selected: Bool) -> some View {
        let playing = it.id == model.item.id
        let rp = user.resumePoint(it)
        let frac: Double = playing ? (vlc.lengthMs > 0 ? min(1, Double(vlc.timeMs) / Double(vlc.lengthMs)) : 0) : (rp?.fraction ?? 0)
        let watched = !playing && (WatchedStore.shared.isWatched(it) || frac > 0.92)
        let pe = PlayerFormat.seasonEpisode(model.item.name)
        let relation: String = {
            guard let pe, pe.season == model.stripSeason else { return "" }
            return e.num == pe.episode + 1 ? " · Next" : (e.num == pe.episode - 1 ? " · Previous" : "")
        }()
        let info: String = {
            if playing { return PlayerFormat.clock(vlc.timeMs / 1000) + " of " + PlayerFormat.clock(max(vlc.lengthMs, e.durationSecs * 1000) / 1000) }
            if let rp, frac > 0.01, !watched { return PlayerFormat.clock(rp.posMs / 1000) + " of " + PlayerFormat.clock(rp.durMs / 1000) }
            return (e.durationSecs > 0 ? PlayerFormat.minutes(e.durationSecs) : "") + relation
        }()
        return Button { model.stripSel = i; model.stripPick(i) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MacImage(url: Img.url(e.still.isEmpty ? model.seriesPoster : e.still, .still)) { MacTheme.tile }.frame(width: cardW, height: 112).clipped()
                    if playing || watched {
                        Text(playing ? "PLAYING" : "WATCHED").font(.system(size: 9, weight: .heavy)).tracking(0.6).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75))).padding(7)
                    }
                    if frac > 0.01 {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.28))
                            Rectangle().fill(Color.white).frame(width: cardW * frac)
                        }
                        .frame(height: 4).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: cardW, height: 112)
                VStack(alignment: .leading, spacing: 2) {
                    Text("E\(e.num) · " + (e.title.isEmpty ? "Episode \(e.num)" : e.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(info).font(.system(size: 11.5)).foregroundStyle(MacTheme.dim).lineLimit(1)
                }
                .padding(.horizontal, 9).frame(width: cardW, height: 46, alignment: .leading)
                .background(panelFill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: selected ? 3 : 0))
        }
        .buttonStyle(.plain).accessibilityIdentifier("episode-card:\(e.num)").accessibilityLabel("Episode \(e.num)")
    }
}

// MARK: - End card (rule 4)

struct EndCardView: View {
    @ObservedObject var model: MacPlayerModel
    let card: MacPlayerModel.EndCard

    var body: some View {
        HStack(spacing: 12) {
            Button { model.acceptCard() } label: {
                HStack(spacing: 12) {
                    MacImage(url: Img.url(thumb, .still)) { MacTheme.tile }.frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kicker).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(MacTheme.dim)
                        Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(hint).font(.system(size: 11.5)).foregroundStyle(MacTheme.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    ring
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("play-now").accessibilityLabel(title)
        }
        .padding(10).frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 12).fill(panelFill.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            Button { model.dismissCard() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(MacTheme.dim).frame(width: 22, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Keep the credits (Esc)").accessibilityLabel("Keep the credits").accessibilityIdentifier("card-dismiss")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("up-next")
    }

    private var thumb: String {
        switch card.kind { case .episode(let n): return n.img; case .season(let it, _): return it.img; case .home: return model.item.img }
    }
    private var kicker: String {
        switch card.kind {
        case .episode(let n):
            let se = PlayerFormat.seasonEpisode(n.name)
            let e = model.episodes.values.joined().first { $0.id == n.id }
            return "NEXT" + (se.map { " · E\($0.episode)" } ?? "") + (e.map { $0.durationSecs > 0 ? " · " + PlayerFormat.minutes($0.durationSecs).uppercased() : "" } ?? "")
        case .season(_, let s): return "NEXT SEASON · S\(s)"
        case .home: return "THE END"
        }
    }
    private var title: String {
        switch card.kind {
        case .episode(let n): return n.sub.isEmpty ? (n.name.components(separatedBy: " · ").last ?? n.name) : n.sub
        case .season(_, let s): return "Season \(s)"
        case .home: return "Back to Home"
        }
    }
    private var hint: String {
        switch card.kind {
        case .home: return "Return goes back to Home"
        default: return "Return plays now · Esc keeps the credits"
        }
    }
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
            if let r = card.ring {
                Circle().trim(from: 0, to: CGFloat(r) / CGFloat(MacPlayerModel.ringSecs)).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: r)
                Text("\(r)").font(.system(size: 15, weight: .bold)).monospacedDigit()
            } else {
                Image(systemName: card.kind == .home ? "house.fill" : "play.fill").font(.system(size: 14))
            }
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Still watching (rule 6)

struct StillWatchingToast: View {
    @ObservedObject var model: MacPlayerModel
    let ask: MacPlayerModel.StillAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Still watching?").font(.system(size: 15, weight: .bold))
            Text("No key press for 2 episodes. Playback pauses in 60 s and frees your account's stream for other devices.")
                .font(.system(size: 12)).foregroundStyle(MacTheme.dim).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Keep watching") { model.keepWatching() }.buttonStyle(MacPill(primary: true)).accessibilityIdentifier("keep-watching")
                Button("Back to Home") { model.stillBackToHome() }.buttonStyle(MacPill()).accessibilityIdentifier("still-home")
                Spacer()
                Text(String(format: "%d:%02d", ask.left / 60, ask.left % 60)).font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.dim)
            }
        }
        .padding(14).frame(width: 480)
        .background(RoundedRectangle(cornerRadius: 12).fill(panelFill.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain).accessibilityIdentifier("still-watching")
    }
}
