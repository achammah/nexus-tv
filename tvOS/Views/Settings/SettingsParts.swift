import SwiftUI

// The building blocks of the Settings page (design: work/frame-tv/design/settings): small-caps header, a grouped panel of rows,
// a row = label + small help on the left, value / pills / toggle / chevron on the right, white outline when focused.

/// A row of a group: the .tile focus (white 4 pt ring, 14 pt corners) without the lift, plus a lighter fill.
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }
    struct Face: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(focused ? Color.white.opacity(0.12) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white, lineWidth: focused ? 4 : 0))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(focused && configuration.isPressed ? 0.99 : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

/// A section of the left column: the selected one (or the focused one) is a white pill.
struct SettingsSideStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, selected: selected) }
    struct Face: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(selected || focused ? Color.black : Color.white.opacity(0.85))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected || focused ? Color.white : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(Theme.ease, value: focused)
        }
    }
}

/// A pill inside a row (Switch, Rename, Move, a menu tab): white when on, a faint capsule when off, a white ring when focused.
struct SettingsPillStyle: ButtonStyle {
    var on = false
    var font: CGFloat = 22
    var destructive = false
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, s: self) }
    struct Face: View {
        let configuration: Configuration
        let s: SettingsPillStyle
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.ui(s.font, s.on || focused ? .semibold : .regular)).lineLimit(1)
                .padding(.horizontal, 22).frame(height: 52)
                .foregroundStyle(s.on ? Color.black : (s.destructive ? Theme.red : Color.white.opacity(focused ? 1 : 0.75)))
                .background(Capsule().fill(s.on ? Color.white : Color.white.opacity(focused ? 0.22 : 0.08)))
                .overlay(Capsule().strokeBorder(Color.white, lineWidth: focused ? 4 : 0))
                .scaleEffect(focused ? (configuration.isPressed ? 1.0 : 1.04) : 1)
                .animation(Theme.ease, value: focused)
        }
    }
}

struct SHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.ui(22, .bold)).tracking(1.2)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.leading, 24).padding(.top, 26).padding(.bottom, 12)
    }
}

/// A grouped panel: rounded, faint fill, hairlines between rows.
struct SGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .offset(y: -1)                                       // hides the first row's top hairline under the clip
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// What every row looks like: label + help on the left, the trailing view on the right.
struct SRowLabel<Trailing: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(28)).lineLimit(1)
                if let help, !help.isEmpty { Text(help).font(.ui(20)).foregroundStyle(.white.opacity(0.45)).lineLimit(2) }
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) { trailing() }.font(.ui(24)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .frame(minHeight: 92)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .foregroundStyle(.white)
    }
}

/// A row you can select.
struct SRow<Trailing: View>: View {
    let title: String
    var help: String? = nil
    var chevron = true
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        Button(action: action) {
            SRowLabel(title: title, help: help) {
                trailing()
                if chevron { Image(systemName: "chevron.right").font(.ui(22, .semibold)).foregroundStyle(.white.opacity(0.35)) }
            }
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// A row that only informs (nothing to select).
struct SInfo<Trailing: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View { SRowLabel(title: title, help: help, trailing: trailing) }
}

/// The on/off capsule of the design (green when on).
struct SToggle: View {
    let on: Bool
    var body: some View {
        Capsule().fill(on ? Color(red: 0.204, green: 0.78, blue: 0.349) : Color.white.opacity(0.2))
            .frame(width: 70, height: 40)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Color.white).frame(width: 32, height: 32).padding(4) }
            .animation(Theme.ease, value: on)
    }
}

struct SBadge: View {
    let text: String
    var fill: Color = Color.white.opacity(0.14)
    var body: some View {
        Text(text.uppercased()).font(.ui(15, .bold)).tracking(0.6).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
    }
}

extension SourceType {
    /// The badge colours of the design: Xtream blue, M3U orange, portal green.
    var badge: (text: String, fill: Color) {
        switch self {
        case .xtream: ("Xtream", Color(red: 0.29, green: 0.39, blue: 1))
        case .m3u: ("M3U", Color(red: 0.71, green: 0.34, blue: 0.16))
        case .portal: ("Portal", Color(red: 0.12, green: 0.56, blue: 0.29))
        }
    }
}
