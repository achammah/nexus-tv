import SwiftUI

/// What Home (and the other pages) show when there is no source yet, or the source holds nothing:
/// "Your library is empty" and one button, "Add a source". Used by the window itself after "Skip for now";
/// the Mac pages and the Apple TV screens can show the same view where a page would otherwise be blank.
struct LibraryEmptyState: View {
    var title = "Your library is empty"
    var detail = "Add a source to see your channels, films and series here."
    var button = "Add a source"
    let add: () -> Void
    #if os(tvOS)
    private let u: CGFloat = 1.42
    #else
    private let u: CGFloat = 1
    #endif

    var body: some View {
        VStack(spacing: 14 * u) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 40 * u, weight: .light)).foregroundStyle(.white.opacity(0.35))
            Text(title).font(.system(size: 24 * u, weight: .bold)).foregroundStyle(.white)
            Text(detail).font(.system(size: 14 * u)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).frame(maxWidth: 420 * u)
            Button(action: add) {
                HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 13 * u, weight: .bold)); Text(button).font(.system(size: 15 * u, weight: .semibold)) }
                    .foregroundStyle(.black).padding(.horizontal, 22 * u).frame(height: 42 * u).background(Capsule().fill(.white))
            }
            .buttonStyle(.plain).padding(.top, 8 * u)
            .accessibilityIdentifier("empty-add-source")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain).accessibilityIdentifier("library-empty")
    }
}
