import SwiftUI

/// Settings (design: work/frame-tv/design/settings): a left column of 7 sections, each with a live summary,
/// and a right pane of small-caps headers and grouped rows. Panes and building blocks live in tvOS/Views/Settings/.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case account = "Account & sources", channels = "Channels", home = "Home & views", lists = "Lists"
        case playback = "Playback & subtitles", data = "Data & storage", about = "About"
        var id: String { rawValue }
    }
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var user: UserStore
    @ObservedObject private var osub = OpenSubtitles.shared
    @State private var section: Section = .account
    @State private var overlay: SettingsOverlay? = nil
    @FocusState private var side: Section?
    @State private var returnTo: Section = .account

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Settings").font(.ui(40, .bold))
                    Text("\u{203A}").font(.ui(40, .light)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal, 16)
                    Text(section.rawValue).font(.ui(40)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 150).padding(.bottom, 30)
                HStack(alignment: .top, spacing: 58) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Section.allCases) { s in
                            Button { section = s } label: {
                                HStack {
                                    Text(s.rawValue).font(.ui(28, s == section ? .semibold : .regular))
                                    Spacer(minLength: 8)
                                    Text(summary(s)).font(.ui(20)).opacity(0.5)
                                }
                                .padding(.horizontal, 26).frame(width: 470, height: 84, alignment: .leading)
                            }
                            .buttonStyle(SettingsSideStyle(selected: s == section))
                            .focused($side, equals: s)
                        }
                    }
                    .frame(width: 470, alignment: .topLeading)
                    .focusSection()

                    ScrollView(.vertical, showsIndicators: false) {
                        pane
                            .padding(.horizontal, 8).padding(.bottom, 60)
                            .frame(width: 1168, alignment: .topLeading)
                    }
                    .frame(width: 1168, height: 790)
                    .focusSection()
                }
            }
            .padding(.leading, Theme.x0)
            .disabled(overlay != nil)

            if let o = overlay {
                Color.black.ignoresSafeArea()      // opaque: nothing of the Settings screen shows behind a picker
                Group {
                    switch o {
                    case .addList: ListPicker(close: { overlay = nil })
                    case .channels(let cc): ChannelPicker(close: { overlay = nil }, start: cc)
                    case .osub: OSubForm(close: { overlay = nil })
                    case .countries: CountriesPicker(close: { overlay = nil })
                    case .languages: LanguagesPicker(close: { overlay = nil })
                    }
                }
                .onExitCommand { overlay = nil }
            }
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
        .onChange(of: side) { _, s in if let s { section = s } }
        // closing a picker comes back to the section it was opened from
        .onChange(of: overlay) { _, o in
            if o != nil { returnTo = section; return }
            section = returnTo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { section = returnTo; side = returnTo }
        }
    }

    @ViewBuilder private var pane: some View {
        let open: (SettingsOverlay) -> Void = { overlay = $0 }
        switch section {
        case .account: AccountPane(open: open)
        case .channels: ChannelsPane(open: open)
        case .home: HomePane()
        case .lists: ListsPane(open: open)
        case .playback: PlaybackPane(open: open)
        case .data: DataPane()
        case .about: AboutPane()
        }
    }

    /// The live summary at the right of each section.
    private func summary(_ s: Section) -> String {
        switch s {
        case .account: return catalog.accounts.isEmpty ? "none" : (catalog.accounts.count == 1 ? "1 active" : "\(catalog.accounts.count) sources")
        case .channels: return "\(settings.countries.count) countries · \(user.favs.count) \u{2605}"
        case .home: return "\(settings.homeRows.filter(\.visible).count) rows"
        case .lists: return "\(settings.lists.count)"
        case .playback:
            let lang = PlaybackPane.lastPick(user)?.audioLang.map { String($0.prefix(2)).uppercased() }
            return [lang, osub.account != nil ? "CC" : nil].compactMap { $0 }.joined(separator: " · ")
        case .data: return ""
        case .about: return AboutPane.version
        }
    }
}
