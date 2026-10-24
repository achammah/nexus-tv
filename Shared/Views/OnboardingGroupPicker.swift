import SwiftUI

/// A very large playlist: while it downloads, this lists every group seen so far with its entry count, and the
/// owner ticks the groups to keep. Same look as the sign-in. Settings › Sources › Choose groups opens it again.
struct GroupPickerView: View {
    @EnvironmentObject var catalog: Catalog
    let state: PickerState
    #if os(tvOS)
    private let u: CGFloat = 1.42
    private let cap = 60_000
    #else
    private let u: CGFloat = 1
    private let cap = 250_000
    #endif
    @State private var ticked = Set<String>()
    @State private var query = ""
    @FocusState private var focus: Bool

    private var visible: [(name: String, n: Int)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? state.groups : state.groups.filter { $0.name.lowercased().contains(q) }
    }
    private var entries: Int { state.groups.filter { ticked.contains($0.name) }.reduce(0) { $0 + $1.n } }
    private static func fmt(_ n: Int) -> String { n.formatted(.number) }
    private static func mb(_ n: Int) -> String { String(format: "%.1f", Double(n) / 1_048_576) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12 * u) {
                Image("Lockup").resizable().scaledToFit().frame(width: 48 * u).opacity(0.82)
                Text("This playlist is very large").font(.system(size: 30 * u, weight: .bold)).foregroundStyle(.white).padding(.top, 18 * u)
                Text("Choose the groups you want. The rest is skipped. You can change this later in Settings, Sources.")
                    .font(.system(size: 15 * u)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                Text(progressText).font(.system(size: 13.5 * u)).foregroundStyle(.white.opacity(0.7)).padding(.top, 12 * u)
                Capsule().fill(.white.opacity(0.08)).frame(height: 2 * u)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(LinearGradient(colors: [Color(red: 211 / 255, green: 148 / 255, blue: 230 / 255), Color(red: 174 / 255, green: 219 / 255, blue: 142 / 255)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * (state.total > 0 ? min(1, Double(state.read) / Double(state.total)) : 0))
                        }
                    }
                Text("\(ticked.count) groups ticked \u{00B7} \(Self.fmt(entries)) entries" + (entries > cap ? " (only the first \(Self.fmt(cap)) are kept)" : " of \(Self.fmt(cap)) allowed"))
                    .font(.system(size: 13.5 * u)).foregroundStyle(entries > cap ? Color(red: 0.988, green: 0.647, blue: 0.647) : .white.opacity(0.55))
                Spacer()
                Text("Nexus TV is a player. It includes no content.").font(.system(size: 12 * u)).foregroundStyle(.white.opacity(0.32))
            }
            .padding(.horizontal, 60 * u).padding(.vertical, 70 * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255))

            VStack(spacing: 14 * u) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.42))
                    TextField("Search groups", text: $query).textFieldStyle(.plain).focused($focus)
                }
                .font(.system(size: 14 * u)).padding(.horizontal, 14 * u).frame(height: 44 * u)
                .background(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).fill(.white.opacity(0.06)))
                HStack(spacing: 10) {
                    pill("Select all") { ticked.formUnion(visible.map(\.name)) }
                    pill("None") { ticked.subtract(visible.map(\.name)) }
                    Spacer()
                    pill("Keep selected", primary: true) { catalog.keepGroups(ticked) }.disabled(ticked.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible, id: \.name) { g in
                            Button { if ticked.contains(g.name) { ticked.remove(g.name) } else { ticked.insert(g.name) } } label: {
                                HStack(spacing: 12 * u) {
                                    Image(systemName: ticked.contains(g.name) ? "checkmark.square.fill" : "square").foregroundStyle(ticked.contains(g.name) ? Color(red: 0.29, green: 0.871, blue: 0.502) : .white.opacity(0.4))
                                    Text(g.name).lineLimit(1)
                                    Spacer()
                                    Text(Self.fmt(g.n)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                                }
                                .font(.system(size: 14 * u)).foregroundStyle(.white).padding(.horizontal, 16 * u).frame(height: 46 * u).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
                        }
                        if visible.isEmpty {
                            Text(state.groups.isEmpty ? "Reading the playlist\u{2026}" : "No group matches this search.").font(.system(size: 14 * u)).foregroundStyle(.white.opacity(0.5)).padding(.top, 30 * u)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14 * u, style: .continuous).fill(.white.opacity(0.05)))
                .clipShape(RoundedRectangle(cornerRadius: 14 * u, style: .continuous))
                HStack { Spacer(); pill("Cancel") { catalog.cancelPicker() } }
            }
            .padding(.horizontal, 60 * u).padding(.vertical, 60 * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255))
        }
        .background(Color.black)
        .accessibilityIdentifier("group-picker")
    }

    private var progressText: String {
        if state.reading { return "Reading the groups you kept\u{2026} \(Self.mb(state.read)) of \(Self.mb(state.total)) MB" }
        if state.done { return "Read \(Self.mb(state.total)) MB. All \(Self.fmt(state.groups.count)) groups are listed." }
        return "Reading \(Self.mb(state.read)) of \(state.total > 0 ? Self.mb(state.total) : "?") MB \u{00B7} \(Self.fmt(state.groups.count)) groups so far"
    }

    private func pill(_ t: String, primary: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 14 * u, weight: .semibold)).foregroundStyle(primary ? .black : .white)
                .padding(.horizontal, 18 * u).frame(height: 36 * u)
                .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}
