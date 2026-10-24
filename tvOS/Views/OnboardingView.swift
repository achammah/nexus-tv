import SwiftUI

/// First launch: the app ships with no account. The owner adds their own Xtream Codes login here; it is checked
/// with the provider and kept in this Apple TV's Keychain. Settings › Accounts adds more later.
struct OnboardingView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    /// A new install opens on the opening; the form fades in over its last frame from 1.8 s.
    @State private var opening = OpeningGate.enabled
    @State private var form = !OpeningGate.enabled

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if opening {
                OpeningView(frozen: OpeningGate.frozenFrame).ignoresSafeArea()
                    .opacity(form ? 0.25 : 1)
                    .task {
                        guard OpeningGate.frozenFrame == nil else { return }
                        try? await Task.sleep(nanoseconds: UInt64(OpeningSpec.homeAt * 1e9))
                        withAnimation(.easeInOut(duration: OpeningSpec.duration - OpeningSpec.homeAt)) { form = true }
                    }
            }
            Group {
                HStack(spacing: 0) {
                    Image("Lockup").resizable().scaledToFit().frame(height: 26).opacity(0.82)      // the mark and "tv" (the opening's last frame), small and quiet
                        .accessibilityLabel("Nexus TV")
                }
                .frame(height: 44)
                .padding(.leading, Theme.x0).padding(.top, 62)
                AccountForm(title: "Add your IPTV account",
                            intro: "Nexus TV plays your own provider’s live channels, films and series (Xtream Codes). Enter the details your provider gave you. They stay in this Apple TV’s Keychain.",
                            saveLabel: "Check and sign in", close: nil) { a in
                    await catalog.onboard(a, languages: settings.languages)
                }
            }
            .opacity(form ? 1 : 0)
            .disabled(!form)
        }
        .frame(width: 1920, height: 1080)
    }
}
