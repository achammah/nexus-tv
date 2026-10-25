import SwiftUI
import AppKit
import VLCKit

/// The player inside the library window: the video fills the window, a floating control bar shows on any mouse move
/// and hides after 3 s. Films and episodes: back 10 s, play/pause, forward 10 s, labelled Audio and Subtitles (popups),
/// Episodes "n of m" (the strip), Next episode once the credits start, picture in picture and full screen (PlayerParts.swift).
/// Live channels keep the small bar with the channel arrows.
/// Keys: space play/pause · ← → 10 s (on the Episodes strip: previous / next episode) · Return plays the strip's or the card's episode ·
/// ↑ ↓ change channel (live; ↓ opens the strip, ↑ closes it for an episode) · F full screen · Esc closes the popup, the strip, the end card
/// (the credits play on), answers the still-watching toast with Keep watching, leaves full screen, PiP, then the player (back to the page it was started from, like the back chevron).
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
            // hidden or minimised: the account's only stream is given back for another device; play reopens it
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in model.saveResume(); model.vlc.release() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in model.saveResume(); model.vlc.release() }
            .onContinuousHover { _ in poke(); model.mouseMoved() }
            .onKeyPress { press in key(press) }
            .onChange(of: model.item) { _, _ in poke() }
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        poke()
        model.keyPressed()
        let strip = model.stripOpen
        switch p.key {
        case .space: if !model.isLive { model.vlc.toggle() }; return .handled
        case .leftArrow:
            if strip { model.stripMove(-1) } else if !model.isLive { model.seek(by: -10_000) }
            return .handled
        case .rightArrow:
            if strip { model.stripMove(1) } else if !model.isLive { model.seek(by: 10_000) }
            return .handled
        case .upArrow:
            if strip { model.closeStrip() } else { model.zap(-1) }
            return .handled
        case .downArrow:
            if model.isLive { model.zap(1) } else if !strip { model.openStrip(); model.stripPinned = true }
            return .handled
        case .escape:
            if model.popup != nil { model.popup = nil }
            else if strip { model.closeStrip() }
            else if model.vlc.lostTo != nil { leave() }
            else if model.still != nil { model.keepWatching() }
            else if model.card != nil { model.dismissCard() }
            else if window.window?.styleMask.contains(.fullScreen) == true { toggleFull() }
            else if pip { togglePip() }
            else { leave() }
            return .handled
        case .return:
            if model.vlc.lostTo != nil { model.vlc.retake(); return .handled }
            if strip { model.stripPick(model.stripSel); return .handled }
            if model.card != nil { model.acceptCard(); return .handled }
            if model.still != nil { model.keepWatching(); return .handled }
            return .ignored
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
            if !Task.isCancelled && dragMs == nil && !(model.vlc.paused && !model.isLive) && !model.stripOpen && model.popup == nil
                && !UserDefaults.standard.bool(forKey: "NXHudStay") {
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

/// Another app took the stream (last device wins): the player let go; Return or a click watches here again, Back leaves.
private struct LostCard: View {
    let by: String
    let watchHere: () -> Void
    let back: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Playing on \(by)").font(.system(size: 26, weight: .bold))
            Text("Your account allows one stream. Press Return to watch here instead.").font(.system(size: 14)).foregroundStyle(MacTheme.soft)
            HStack(spacing: 10) {
                Button("Watch here", action: watchHere).buttonStyle(MacPill(primary: true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("lost-watch-here")
                Button("Back", action: back).buttonStyle(MacPill()).accessibilityIdentifier("lost-back")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
        .accessibilityElement(children: .contain).accessibilityIdentifier("lost-card")
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
            if model.busy { pill(model.busyTaking ? "Taking over from the other device…" : "Your account is in use on another device. Nexus TV starts as soon as it is free.", spinner: true) }
            else if model.reconnecting { pill("Reconnecting…  \(model.attempts)/5", spinner: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24) }
            if vlc.failed { pill("This could not be played") }
            if let by = vlc.lostTo { LostCard(by: by, watchHere: { vlc.retake() }, back: back) }
            if let m = model.message { pill(m).frame(maxHeight: .infinity, alignment: .top).padding(.top, 60) }
            if hudVisible {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 60).frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                Text(model.title).font(.system(size: 13, weight: .semibold)).frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
                    .accessibilityIdentifier("player-title")
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 34, height: 34).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.white).help("Back (Esc)").accessibilityLabel("Back to the page")
                    .accessibilityIdentifier("player-back")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 84).padding(.top, 4)
            }
            if model.popup != nil { Color.clear.contentShape(Rectangle()).onTapGesture { model.popup = nil } }
            if hudVisible && !pip {
                if model.isLive { hud.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 22).transition(.opacity) }
                else { VODLayer(model: model, vlc: vlc, dragMs: $dragMs, togglePip: togglePip, toggleFull: toggleFull).transition(.opacity) }
            }
            if hudVisible && vlc.started && pip { pipBar.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10) }
            // the end card and the still-watching toast sit bottom right, above the bar
            VStack(alignment: .trailing, spacing: 10) {
                if let ask = model.still { StillWatchingToast(model: model, ask: ask).transition(.move(edge: .trailing).combined(with: .opacity)) }
                if let c = model.card, !pip { EndCardView(model: model, card: c).transition(.move(edge: .trailing).combined(with: .opacity)) }
            }
            .padding(.trailing, 24).padding(.bottom, pip ? 60 : (model.isLive ? 100 : (hudVisible ? 146 + (model.stripOpen ? 176 : 0) : 30)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .animation(.easeOut(duration: 0.2), value: model.card)
            .animation(.easeOut(duration: 0.2), value: model.still != nil)
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

    /// The bar of a live channel: the LIVE mark, the channel arrows, audio, subtitles, picture in picture and full screen.
    private var hud: some View {
        HStack(spacing: 16) {
            LivePillMac()
            icon("chevron.up", "Previous channel", 18) { model.zap(-1) }
            icon("chevron.down", "Next channel", 18) { model.zap(1) }
            Spacer()
            audioMenu
            ccMenu
            icon("pip.enter", "Picture in picture", 18, action: togglePip)
            icon("arrow.up.left.and.arrow.down.right", "Full screen", 17, action: toggleFull)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
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
