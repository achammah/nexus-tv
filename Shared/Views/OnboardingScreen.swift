import SwiftUI

/// First launch and "Add a source": a split screen. Brand and features on the left, the sign-in on the right.
/// Same design on the Mac (u = 1) and the Apple TV (u = 1.42).
struct OnboardingScreen: View {
    @ObservedObject var model: OnboardingModel
    /// "Skip for now" (first launch) or "Cancel" (adding a source).
    let skipLabel: String
    let addMode: Bool
    let skip: () -> Void
    let submit: () -> Void

    #if os(tvOS)
    private let u: CGFloat = 1.42
    private let lockWidth: CGFloat = 68
    private let isTV = true
    #else
    private let u: CGFloat = 1
    private let lockWidth: CGFloat = 48
    private let isTV = false
    #endif

    @FocusState private var focus: Field?
    enum Field: Hashable { case row(Int), go, skip, type(Int) }
    @State private var featIn = [false, false, false, false]
    @State private var slide = false
    @State private var shakeX: CGFloat = 0

    private static let features: [(String, String, String, Color)] = [
        ("books.vertical", "Your library, organized", "Whatever your service holds, sorted into clear shelves.", Color(red: 0.906, green: 0.784, blue: 0.949)),
        ("play.circle", "Pick up where you left off", "Resume anything; the next episode starts after a short countdown.", Color(red: 0.788, green: 0.906, blue: 0.702)),
        ("captions.bubble", "Subtitles that stay in sync", "Matched to your file, then realigned while you watch.", Color(red: 0.749, green: 0.816, blue: 1)),
        ("checkmark.shield", "Private by design", "Your sign-in stays on this device. No account with us.", Color(red: 0.953, green: 0.906, blue: 0.969)),
    ]
    private static let red = Color(red: 0.973, green: 0.443, blue: 0.443)
    private static let green = Color(red: 0.29, green: 0.871, blue: 0.502)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 2, h = geo.size.height
            HStack(spacing: 0) {
                left(w, h)
                    .frame(width: w, height: h)
                    .offset(x: model.ending ? -w * 0.3 : 0).opacity(model.ending ? 0 : 1)
                right(w, h)
                    .frame(width: w, height: h)
                    .offset(x: model.ending ? w * 0.3 : 0).opacity(model.ending ? 0 : 1)
            }
            .animation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.9), value: model.ending)
        }
        .onAppear {
            for i in 0..<4 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + 0.13 * Double(i)) { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)) { featIn[i] = true } } }
            #if os(tvOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if focus == nil && !model.frozen { focus = .row(0) } }
            #endif
        }
        .onChange(of: model.shakes) { _, _ in
            withAnimation(.linear(duration: 0.09)) { shakeX = -7 * u }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { withAnimation(.linear(duration: 0.09)) { shakeX = 7 * u } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation(.linear(duration: 0.09)) { shakeX = -4 * u } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { withAnimation(.linear(duration: 0.09)) { shakeX = 0 } }
        }
        .accessibilityElement(children: .contain)      // the rows, the type choice and the buttons keep their own ids
        .accessibilityIdentifier("onboarding")
        #if os(tvOS)
        .onExitCommand { if !model.ending { skip() } }
        #endif
    }

    // MARK: left: brand and features

    private func left(_ w: CGFloat, _ h: CGFloat) -> some View {
        let contentH = 470 * u
        let top = max(40 * u, min(h * 0.17, h - contentH - 70 * u))
        return ZStack(alignment: .topLeading) {
            Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255)
            ZStack(alignment: .topLeading) {
            glow(Color(red: 211 / 255, green: 148 / 255, blue: 230 / 255).opacity(0.26), x: -0.30 * w, y: 0.45 * h, w: 1.10 * w, h: 0.80 * h)
            glow(Color(red: 174 / 255, green: 219 / 255, blue: 142 / 255).opacity(0.13), x: 0.35 * w, y: 0.72 * h, w: 0.80 * w, h: 0.55 * h)
            glow(Color(red: 120 / 255, green: 150 / 255, blue: 1).opacity(0.12), x: 0.55 * w, y: -0.30 * h, w: 0.70 * w, h: 0.55 * h)
            }.frame(width: w, height: h, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 0) {
                Image("Lockup").resizable().interpolation(.high).scaledToFit().frame(width: lockWidth).opacity(0.82)
                    .accessibilityElement().accessibilityLabel("Nexus TV").accessibilityIdentifier("lockup")
                Text("Your media,\nbeautifully organized.")
                    .font(.system(size: 36 * u, weight: .bold)).tracking(-0.7 * u).lineSpacing(0)
                    .foregroundStyle(.white).padding(.top, 34 * u).fixedSize(horizontal: false, vertical: true)
                Text("A player for the service you already have. Sign in once and everything is in its place.")
                    .font(.system(size: 15 * u)).lineSpacing(4 * u).foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: w * 0.75 * 0.92, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 12 * u)
                VStack(alignment: .leading, spacing: 18 * u) {
                    ForEach(0..<4, id: \.self) { i in feature(i) }
                }.padding(.top, 30 * u)
            }
            .frame(width: w * 0.75, alignment: .leading)
            .offset(x: w * 0.125, y: top)
            Text("Nexus TV is a player. It includes no content.")
                .font(.system(size: 12 * u)).foregroundStyle(.white.opacity(0.32))
                .offset(x: w * 0.125, y: h - 36 * u - 16 * u)
        }
        .clipped()
    }

    private func glow(_ c: Color, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Ellipse().fill(c).frame(width: w, height: h).blur(radius: 70 * u).offset(x: x, y: y)
    }

    private func feature(_ i: Int) -> some View {
        let f = Self.features[i]
        return HStack(spacing: 16 * u) {
            Image(systemName: f.0).font(.system(size: 20 * u, weight: .regular)).foregroundStyle(f.3)
                .frame(width: 44 * u, height: 44 * u)
                .background(RoundedRectangle(cornerRadius: 12 * u, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.1).font(.system(size: 15 * u, weight: .semibold)).foregroundStyle(.white)
                Text(f.2).font(.system(size: 13.5 * u)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(featIn[i] ? 1 : 0).offset(y: featIn[i] ? 0 : 10)
    }

    // MARK: right: sign in

    private func right(_ w: CGFloat, _ h: CGFloat) -> some View {
        let contentH = 440 * u
        let top = max(64 * u, min(h * 0.26, h - contentH - 60 * u))
        let busy = model.phase == .checking
        return ZStack(alignment: .topLeading) {
            Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
            VStack(alignment: .leading, spacing: 0) {
                Text(addMode ? "Add a source" : "Sign in").font(.system(size: 26 * u, weight: .bold)).tracking(-0.4 * u).foregroundStyle(.white)
                Text(model.type.sub).font(.system(size: 14 * u)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8 * u)
                typeSwitch.padding(.top, 22 * u)
                form(busy).padding(.top, 14 * u)
                progressLine.padding(.top, 14 * u).opacity(busy ? 1 : 0)
                noteLine.frame(height: 40 * u, alignment: .leading)
                HStack { Spacer(); goButton }.padding(.top, 6 * u)
                hint.padding(.top, 22 * u)
            }
            .frame(width: w * 0.72, alignment: .leading)
            .offset(x: w * 0.14 + shakeX, y: top)
        }
        .overlay(alignment: .topTrailing) { skipPill.padding(.trailing, 28 * u).padding(.top, 18 * u) }
    }

    private var skipPill: some View {
        Button(action: skip) {
            Text(skipLabel).font(.system(size: 13 * u)).foregroundStyle(.white.opacity(focus == .skip && isTV ? 1 : 0.6))
                .padding(.horizontal, 14 * u).frame(height: 30 * u)
                .background(Capsule().fill(.white.opacity(isTV && focus == .skip ? 0.2 : 0.06)))
        }
        .buttonStyle(PlainPress())
        .focused($focus, equals: .skip)
        .opacity(model.ending ? 0 : 1)
        .accessibilityIdentifier("onboarding-skip")
    }

    private var typeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(Array(SourceType.allCases.enumerated()), id: \.offset) { i, t in
                let on = model.type == t
                Button { model.type = t } label: {
                    Text(t.title).font(.system(size: 13.5 * u, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? (isTV ? Color.black : Color.white) : .white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 32 * u)
                        .background(RoundedRectangle(cornerRadius: 9 * u, style: .continuous).fill(on ? (isTV ? Color.white : Color.white.opacity(0.14)) : (isTV && focus == .type(i) ? Color.white.opacity(0.18) : .clear)))
                }
                .buttonStyle(PlainPress())
                .focused($focus, equals: .type(i))
                .disabled(model.phase == .checking)
                .accessibilityIdentifier("onboarding-type-" + t.rawValue)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func form(_ busy: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                if i > 0 { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
                row(i, busy)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14 * u, style: .continuous).fill(.white.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 14 * u, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14 * u, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
        .opacity(busy ? 0.6 : 1)
        .animation(.easeOut(duration: 0.3), value: busy)
    }

    private func row(_ i: Int, _ busy: Bool) -> some View {
        let spec = model.type.rows[i]
        let mark = model.marks[i]
        let focused = focus == .row(i) || (model.frozen && model.staticFocus == i)
        let tvFocus = isTV && focus == .row(i)
        let fg: Color = tvFocus ? .black : .white
        return HStack(spacing: 12 * u) {
            Image(systemName: spec.icon).font(.system(size: 14 * u)).frame(width: 17 * u)
                .foregroundStyle(tvFocus ? Color.black : .white.opacity(0.42))
            Text(spec.label).font(.system(size: 14 * u)).foregroundStyle(fg.opacity(tvFocus ? 1 : 0.72)).frame(width: 86 * u, alignment: .leading)
            field(i, fg: fg, tvFocus: tvFocus, focused: focused, busy: busy)
            ZStack {
                Circle().fill(mark == .ok ? Self.green : Self.red)
                Image(systemName: mark == .ok ? "checkmark" : "xmark").font(.system(size: 10 * u, weight: .heavy)).foregroundStyle(.black)
            }
            .frame(width: 20 * u, height: 20 * u)
            .scaleEffect(mark == .none ? 0.4 : 1).opacity(mark == .none ? 0 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: mark)
        }
        .padding(.horizontal, 16 * u).frame(height: 52 * u)
        .background(tvFocus ? Color.white : (mark == .bad ? Self.red.opacity(0.08) : (focused ? Color.white.opacity(0.09) : .clear)))
        .overlay(alignment: .leading) { Rectangle().fill(mark == .ok ? Self.green : (mark == .bad ? Self.red : .clear)).frame(width: 3) }
        .animation(.easeOut(duration: 0.3), value: mark)
        .contentShape(Rectangle())
        #if !os(tvOS)
        .onTapGesture { if !model.frozen { focus = .row(i) } }
        #endif
    }

    @ViewBuilder private func field(_ i: Int, fg: Color, tvFocus: Bool, focused: Bool, busy: Bool) -> some View {
        let spec = model.type.rows[i]
        let secret = model.type == .xtream && i == 2
        let text = Binding(get: { model.rows[i] }, set: { model.set(i, $0) })
        ZStack(alignment: .leading) {
            if model.rows[i].isEmpty {
                HStack(spacing: 0) {
                    Text(spec.hint).font(.system(size: 14 * u)).foregroundStyle(tvFocus ? Color.black.opacity(0.4) : .white.opacity(0.3))
                    if model.frozen && focused { caret }
                }
            }
            if model.frozen {
                Text(model.rows[i]).font(.system(size: 14 * u)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
            } else if secret {
                SecureField("", text: text).textFieldStyle(.plain).font(.system(size: 14 * u)).foregroundStyle(fg.opacity(0.92))
                    .focused($focus, equals: .row(i)).onSubmit { advance(i) }.disabled(busy)
                    .accessibilityIdentifier("onboarding-field-\(i)")
            } else {
                TextField("", text: text).textFieldStyle(.plain).font(.system(size: 14 * u)).foregroundStyle(fg.opacity(0.92))
                    .focused($focus, equals: .row(i)).onSubmit { advance(i) }.disabled(busy)
                    .autocorrectionDisabled()
                    #if os(tvOS)
                    .textContentType(i == 0 ? .URL : nil)
                    #endif
                    .accessibilityIdentifier("onboarding-field-\(i)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caret: some View {
        Rectangle().fill(.white).frame(width: 1.5, height: 15 * u).padding(.leading, 1)
    }

    /// Return moves to the next row; after the last one it signs in.
    private func advance(_ i: Int) { if i < 2 { focus = .row(i + 1) } else { submit() } }

    private var progressLine: some View {
        ProgressSlide(u: u).frame(height: 2)
    }

    private var noteLine: some View {
        HStack(spacing: 8) {
            if model.note == .wait { OnbSpinner(size: 16 * u) }
            else if model.note == .bad { Image(systemName: "xmark").font(.system(size: 13 * u, weight: .semibold)) }
            else if model.note == .ok { Image(systemName: "checkmark").font(.system(size: 13 * u, weight: .semibold)) }
            Text(model.noteText).font(.system(size: 13.5 * u)).lineLimit(2)
        }
        .foregroundStyle(model.note == .bad ? Color(red: 0.988, green: 0.647, blue: 0.647) : model.note == .ok ? Color(red: 0.525, green: 0.937, blue: 0.675) : .white.opacity(0.5))
        .opacity(model.note == .none ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: model.note)
        .accessibilityIdentifier("onboarding-message")
    }

    private var goButton: some View {
        let busy = model.phase == .checking, done = model.phase == .done
        return Button(action: submit) {
            HStack(spacing: 10) {
                Text(busy ? "Checking" : done ? (addMode ? "Added" : "Signed in") : "Sign in").font(.system(size: 15 * u, weight: .semibold))
                if busy { OnbSpinner(size: 17 * u, color: .black) }
                else { Image(systemName: done ? "checkmark" : "arrow.right").font(.system(size: 14 * u, weight: .bold)) }
            }
            .foregroundStyle(done ? Color(red: 0.02, green: 0.18, blue: 0.086) : .black)
            .padding(.horizontal, 22 * u).frame(height: 42 * u)
            .background(Capsule().fill(done ? Self.green : Color.white.opacity(busy ? 0.75 : 1)))
            .scaleEffect(isTV && focus == .go ? 1.08 : 1)
            .shadow(color: .black.opacity(isTV && focus == .go ? 0.6 : 0), radius: 18)
        }
        .buttonStyle(PlainPress())
        .focused($focus, equals: .go)
        .disabled(busy || done)
        .keyboardShortcutIfMac()
        .accessibilityIdentifier("onboarding-go")
    }

    private var hint: some View {
        Group {
            #if os(tvOS)
            (Text("Type from your iPhone: ").foregroundColor(.white.opacity(0.6)) + Text("a keyboard notification appears on it when a field is selected."))
            #else
            Text("Where do I find these? In the welcome email or app your service sent you.")
            #endif
        }
        .font(.system(size: 13 * u)).lineSpacing(3 * u).foregroundStyle(.white.opacity(0.38))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: pieces

private struct PlainPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private extension View {
    @ViewBuilder func keyboardShortcutIfMac() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.defaultAction)
        #else
        self
        #endif
    }
}

struct OnbSpinner: View {
    var size: CGFloat
    var color: Color = .white
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.75).stroke(color, style: StrokeStyle(lineWidth: max(1.5, size / 9), lineCap: .round))
            .frame(width: size * 0.85, height: size * 0.85).rotationEffect(.degrees(spin ? 360 : 0))
            .frame(width: size, height: size)
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

/// A thin line with a gradient segment that slides across, while a check runs.
struct ProgressSlide: View {
    var u: CGFloat
    @State private var go = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [Color(red: 211 / 255, green: 148 / 255, blue: 230 / 255), Color(red: 174 / 255, green: 219 / 255, blue: 142 / 255)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * 0.3)
                    .offset(x: go ? g.size.width * 1.1 : -g.size.width * 0.3)
            }
            .clipShape(Capsule())
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { go = true } }
        }
    }
}
