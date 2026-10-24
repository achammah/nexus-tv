import SwiftUI
import AppKit
import VLCKit

/// The player inside the library window: the video fills the window, a floating control bar shows on any mouse move
/// and hides after 3 s,
/// back 10 s, play/pause, forward 10 s, audio, CC (file + online subtitles, Earlier / Later), next episode with a
/// small picture of it, picture in picture (a small window on top of the others) and full screen.
/// Keys: space play/pause · ← → 10 s · ↑ ↓ change channel (live) · F full screen · Esc leaves full screen, PiP, then the
/// player (back to the page it was started from, like the back chevron).
struct MacPlayerView: View {
    let start: MacPlay
    let window: WindowRef
    let close: () -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var user: UserStore
    @EnvironmentObject var settings: Settings
    @StateObject private var model: MacPlayerModel
    @ObservedObject private var osub = OpenSubtitles.shared
    @State private var hudVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var pip = false
    @State private var dragMs: Int? = nil
    @FocusState private var focused: Bool

    init(start: MacPlay, window: WindowRef, close: @escaping () -> Void) {
        self.start = start; self.window = window; self.close = close
        _model = StateObject(wrappedValue: MacPlayerModel(start))
    }

    var body: some View {
        PlayerBody(model: model, vlc: model.vlc, hudVisible: hudVisible, pip: pip, dragMs: $dragMs,
                   togglePip: togglePip, toggleFull: toggleFull, back: leave)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear {
                focused = true
                model.attach(catalog: catalog, user: user, languages: settings.languages)
                model.onEnd = { leave() }
                model.start()
                poke()
            }
            .onDisappear { model.stop() }
            .onContinuousHover { _ in poke() }
            .onKeyPress { press in key(press) }
            .onChange(of: model.item) { _, _ in poke() }
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        poke()
        switch p.key {
        case .space: if !model.isLive { model.vlc.toggle() }; return .handled
        case .leftArrow: if !model.isLive { model.seek(by: -10_000) }; return .handled
        case .rightArrow: if !model.isLive { model.seek(by: 10_000) }; return .handled
        case .upArrow: model.zap(-1); return .handled
        case .downArrow: model.zap(1); return .handled
        case .escape:
            if model.upLeft > 0 { model.upHide() }
            else if window.window?.styleMask.contains(.fullScreen) == true { toggleFull() }
            else if pip { togglePip() }
            else { leave() }
            return .handled
        case .return: if model.upLeft > 0 { model.playNext(); return .handled }; return .ignored
        default:
            if p.characters.lowercased() == "f" { toggleFull(); return .handled }
            return .ignored
        }
    }

    /// The control bar shows on any mouse move or key, and hides after 3 s.
    private func poke() {
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // -NXHudStay YES keeps the bar up (screenshots)
            if !Task.isCancelled && dragMs == nil && !(model.vlc.paused && !model.isLive) && !UserDefaults.standard.bool(forKey: "NXHudStay") {
                withAnimation(.easeOut(duration: 0.25)) { hudVisible = false }
            }
        }
    }

    private func toggleFull() { window.window?.toggleFullScreen(nil) }

    /// Back to the page the player was started from (picture in picture undone first).
    private func leave() {
        if pip { togglePip() }
        model.stop()
        close()
    }

    /// Picture in picture: the window becomes small, on top of every other window and on every desktop; again to restore.
    private func togglePip() {
        guard let w = window.window else { return }
        if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        if !pip {
            window.saved = w.frame
            let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let size = NSSize(width: 480, height: 270)
            w.level = .floating
            w.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            w.setFrame(NSRect(x: vis.maxX - size.width - 20, y: vis.minY + 20, width: size.width, height: size.height), display: true, animate: true)
        } else {
            w.level = .normal
            w.collectionBehavior.remove(.canJoinAllSpaces)
            if let f = window.saved { w.setFrame(f, display: true, animate: true) }
        }
        pip.toggle()
    }
}

/// The parts that redraw on every clock tick.
private struct PlayerBody: View {
    @ObservedObject var model: MacPlayerModel
    @ObservedObject var vlc: VLCController
    let hudVisible: Bool
    let pip: Bool
    @Binding var dragMs: Int?
    let togglePip: () -> Void
    let toggleFull: () -> Void
    let back: () -> Void
    @ObservedObject private var osub = OpenSubtitles.shared

    var body: some View {
        ZStack {
            Color.black
            MacVideoView(controller: vlc)
            if !vlc.started && !vlc.failed && !model.reconnecting { loading }
            if model.reconnecting { pill("Reconnecting…  \(model.attempts)/5", spinner: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24) }
            if vlc.failed { pill("This could not be played") }
            if let m = model.message { pill(m).frame(maxHeight: .infinity, alignment: .top).padding(.top, 60) }
            if hudVisible || model.upLeft > 0 {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 60).frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                Text(model.title).font(.system(size: 13, weight: .semibold)).frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
                    .accessibilityIdentifier("player-title")
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 34, height: 34).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.white).help("Back (Esc)").accessibilityLabel("Back to the page")
                    .accessibilityIdentifier("player-back")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 84).padding(.top, 4)
            }
            if hudVisible && !pip { hud.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 22).transition(.opacity) }
            if hudVisible && vlc.started && pip { pipBar.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10) }
            if model.upLeft > 0, let n = model.next.first { upNext(n).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(30) }
        }
        .ignoresSafeArea()
        .frame(minWidth: 320, minHeight: 180)
    }

    private var loading: some View {
        VStack(spacing: 14) {
            Text(model.item.name).font(.system(size: 24, weight: .bold))
            Text(model.isLive ? "Tuning in  \(vlc.loadPct)%" : (model.startMs > 0 ? "Resuming at \(fmt(model.startMs))  ·  \(vlc.loadPct)%" : "Loading  \(vlc.loadPct)%"))
                .font(.system(size: 14)).monospacedDigit().foregroundStyle(MacTheme.soft)
            ProgressView(value: Double(max(4, vlc.loadPct)), total: 100).frame(width: 320).tint(.white)
        }
    }

    private func pill(_ t: String, spinner: Bool = false) -> some View {
        HStack(spacing: 10) { if spinner { ProgressView().controlSize(.small) }; Text(t).font(.system(size: 14, weight: .semibold)) }
            .padding(.horizontal, 18).padding(.vertical, 10).background(Capsule().fill(Color.black.opacity(0.75)))
    }

    private var hud: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                if !model.isLive {
                    icon("gobackward.10", "Back 10 seconds", 22) { model.seek(by: -10_000) }
                    icon(vlc.paused ? "play.fill" : "pause.fill", vlc.paused ? "Play" : "Pause", 28) { vlc.toggle() }
                    icon("goforward.10", "Forward 10 seconds", 22) { model.seek(by: 10_000) }
                } else {
                    LivePillMac()
                    icon("chevron.up", "Previous channel", 18) { model.zap(-1) }
                    icon("chevron.down", "Next channel", 18) { model.zap(1) }
                }
                Spacer()
                audioMenu
                ccMenu
                if let n = model.next.first, !model.isLive {
                    Button { model.playNext() } label: {
                        HStack(spacing: 8) {
                            MacImage(url: Img.url(n.img, .still)) { MacTheme.tile }.frame(width: 48, height: 27).clipShape(RoundedRectangle(cornerRadius: 4))
                            Image(systemName: "forward.end.fill").font(.system(size: 11))
                            Text("Next episode").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.leading, 4).padding(.trailing, 12).frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.12))).overlay(Capsule().stroke(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain).help(n.name + (n.sub.isEmpty ? "" : " · " + n.sub))
                    .accessibilityLabel("Next episode").accessibilityIdentifier("next-episode")
                }
                icon("pip.enter", "Picture in picture", 18, action: togglePip)
                icon("arrow.up.left.and.arrow.down.right", "Full screen", 17, action: toggleFull)
            }
            if !model.isLive { timeline }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, model.isLive ? 12 : 14)
        .frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255).opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain).accessibilityIdentifier("hud")
    }

    private var pipBar: some View {
        HStack(spacing: 18) {
            icon(vlc.paused ? "play.fill" : "pause.fill", vlc.paused ? "Play" : "Pause", 18) { vlc.toggle() }
            icon("pip.exit", "Leave picture in picture", 16, action: togglePip)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Color.black.opacity(0.6)))
    }

    private var timeline: some View {
        let shown = dragMs ?? vlc.timeMs
        return HStack(spacing: 12) {
            Text(fmt(shown)).font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.soft)
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
                    .onEnded { _ in if let d = dragMs { vlc.seek(toMs: d) }; dragMs = nil })
            }
            .frame(height: 16)
            .accessibilityElement().accessibilityLabel("Timeline").accessibilityValue(fmt(shown)).accessibilityIdentifier("timeline")
            Text(vlc.lengthMs > 0 ? "−" + fmt(max(0, vlc.lengthMs - shown)) : "").font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.soft)
        }
    }

    private var audioMenu: some View {
        let list = vlc.audioTracks
        return Menu {
            if list.count < 2 { Text("Only one audio track") }
            ForEach(list, id: \.0) { t in
                Button { model.choose(audio: t) } label: {
                    if t.0 == vlc.audioIndex { Label(vlc.audioLabel(t, in: list), systemImage: "checkmark") } else { Text(vlc.audioLabel(t, in: list)) }
                }
            }
        } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 18)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Audio").accessibilityIdentifier("audio-menu")
    }

    private var ccMenu: some View {
        let embedded = vlc.subtitleTracks.filter { $0.0 != model.onlineTrack }
        let current = vlc.subtitleIndex
        let onlineOn = model.onlineTrack != nil && current == model.onlineTrack
        return Menu {
            ForEach(embedded, id: \.0) { t in
                let name = t.0 < 0 ? "Off" : VLCController.trackLabel(t, in: embedded)
                Button { model.choose(subtitle: t) } label: { if t.0 == current && !onlineOn { Label(name, systemImage: "checkmark") } else { Text(name) } }
            }
            if embedded.isEmpty { Text("No subtitles in this file") }
            if osub.ready {
                Section("Online · OpenSubtitles") {
                    if model.onlineState == "loading" || model.onlineState.isEmpty { Text("Searching…") }
                    else if model.onlineState != "done" { Text(model.onlineState) }
                    ForEach(model.online) { r in
                        let name = OpenSubtitles.languageName(r.lang) + " · online" + MacPlayerModel.releaseHint(r.release)
                        Button { Task { await model.pickOnline(r, remember: true) } } label: {
                            if onlineOn && model.onlineActive == r.fileId { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                }
                if onlineOn {
                    Section("Timing \(String(format: "%+.1f", Double(vlc.subtitleDelayMs) / 1000)) s") {
                        Button("Earlier −0.5 s") { model.shiftDelay(-500) }
                        Button("Later +0.5 s") { model.shiftDelay(500) }
                    }
                }
            }
        } label: { Image(systemName: "captions.bubble").font(.system(size: 18)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Subtitles").accessibilityIdentifier("cc-menu")
    }

    private func upNext(_ n: MediaItem) -> some View {
        let ep = n.name.components(separatedBy: " · ").last ?? n.name
        return HStack(spacing: 16) {
            MacImage(url: Img.url(n.img, .still)) { MacTheme.tile }.frame(width: 160, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT EPISODE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(MacTheme.dim)
                Text(n.sub.isEmpty ? ep : ep + " · " + n.sub).font(.system(size: 15, weight: .semibold)).lineLimit(2).frame(width: 240, alignment: .leading)
                HStack(spacing: 10) {
                    Button { model.playNext() } label: { Label("Play now · \(model.upLeft)", systemImage: "play.fill").monospacedDigit() }
                        .buttonStyle(MacPill(primary: true)).accessibilityIdentifier("play-now")
                    Button("Keep watching") { model.upHide() }.buttonStyle(MacPill())
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain).accessibilityIdentifier("up-next")
    }

    private func icon(_ name: String, _ label: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: size, weight: .medium)).frame(width: size + 10, height: size + 10).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.white).help(label).accessibilityLabel(label)
    }

    private func fmt(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct LivePillMac: View {
    var body: some View {
        Text("LIVE").font(.system(size: 10, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 4).fill(Color.red))
    }
}

struct MacVideoView: NSViewRepresentable {
    let controller: VLCController
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        controller.player.drawable = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The NSWindow behind a SwiftUI view (picture in picture, full screen, close).
final class WindowRef { weak var window: NSWindow?; var saved: NSRect? }
struct WindowAccessor: NSViewRepresentable {
    let ref: WindowRef
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { ref.window = v.window; v.window?.isMovableByWindowBackground = true }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { if ref.window == nil { DispatchQueue.main.async { ref.window = nsView.window } } }
}
