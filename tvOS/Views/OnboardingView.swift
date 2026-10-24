import SwiftUI

/// First launch: the split-screen sign-in (Xtream login, M3U playlist or Portal), checked before it is saved.
/// "Skip for now" lands on Home with its empty state. Settings › Sources adds more later.
struct OnboardingView: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @ObservedObject var model: OnboardingModel
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
                        withAnimation(.easeInOut(duration: OpeningSpec.fadeOut)) { form = true }
                    }
            }
            OnboardingScreen(model: model, skipLabel: addMode ? "Cancel" : "Skip for now", addMode: addMode, skip: skip, submit: submit)
                .opacity(form ? 1 : 0)
                .disabled(!form)
        }
        .frame(width: 1920, height: 1080)
    }

    private var addMode: Bool { model.lockedAdd ?? (!catalog.needsAccount && !model.frozen) }
    private func skip() {
        if model.frozen { return }
        if addMode { catalog.addingSource = false; model.reset() } else { catalog.onboardingSkipped = true }
    }
    private func submit() {
        model.submit(catalog: catalog, languages: settings.languages, addMode: addMode) { catalog.addingSource = false }
    }
}
