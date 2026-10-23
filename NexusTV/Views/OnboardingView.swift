import SwiftUI

/// First launch: the app ships with no account. The owner adds their own Xtream Codes login here; it is checked
/// with the provider and kept in this Apple TV's Keychain. Settings › Accounts adds more later.
struct OnboardingView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                Image("NexusLogo").resizable().scaledToFit().frame(height: 40).padding(.top, 2)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 2, height: 32).padding(.leading, 18).padding(.trailing, 16)
                Text("TV").font(.ui(36, .light)).tracking(3)
            }
            .frame(height: 44)
            .padding(.leading, Theme.x0).padding(.top, 62)
            AccountForm(title: "Add your IPTV account",
                        intro: "Nexus TV plays your own provider’s live channels, films and series (Xtream Codes). Enter the details your provider gave you. They stay in this Apple TV’s Keychain.",
                        saveLabel: "Check and sign in", close: nil) { a in
                await catalog.onboard(a, languages: settings.languages)
            }
        }
        .frame(width: 1920, height: 1080)
    }
}
