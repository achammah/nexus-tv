import SwiftUI

// Live (design A): pinned countries as big flag cards, regions as gradient cards, then every country A to Z.
// A card opens that country's page (LiveBrowsePage).

struct LivePage: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: MacNav

    var body: some View {
        let dir = LiveDirectory(catalog: catalog, pinned: settings.countries)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !dir.pinned.isEmpty {
                    LiveSection(title: "Pinned", note: "your countries · change in Settings")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), alignment: .leading, spacing: 14) {
                        ForEach(dir.pinned) { c in
                            PinnedButton(entry: c) { nav.go(.live(c.code)) }
                                .accessibilityIdentifier("live:pinned:" + c.code)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                if !dir.regions.isEmpty {
                    LiveSection(title: "Regions", note: "\(dir.regions.count)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(dir.regions) { r in
                                Button { nav.go(.live(r.code)) } label: { RegionCard(entry: r) }
                                    .buttonStyle(.plain).accessibilityIdentifier("live:region:" + r.region.id)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                }
                if !dir.all.isEmpty {
                    LiveSection(title: "All countries", note: "\(dir.all.count) · A to Z")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), alignment: .leading, spacing: 8) {
                        ForEach(dir.all) { c in
                            Button { nav.go(.live(c.code)) } label: { CountryChip(entry: c) }
                                .buttonStyle(.plain).accessibilityIdentifier("live:country:" + c.code)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                if dir.pinned.isEmpty && dir.regions.isEmpty && dir.all.isEmpty {
                    Text("Live channels show here once the account has loaded.").foregroundStyle(MacTheme.dim).padding(40)
                }
            }
            .padding(.bottom, 30)
        }
        .task { await catalog.ensureLiveIndex() }
    }
}

private struct LiveSection: View {
    let title: String, note: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text(note).font(.system(size: 13)).foregroundStyle(MacTheme.dim)
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 14)
    }
}

private struct RegionCard: View {
    let entry: LiveRegionEntry
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [entry.region.from.opacity(0.8), entry.region.to.opacity(0.67)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "globe").font(.system(size: 78, weight: .light)).opacity(0.28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 14, y: -8)
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(entry.region.title).font(.system(size: 14.5, weight: .bold)).lineLimit(1)
                Text(CountryNames.groups(entry.groups)).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: 176, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CountryChip: View {
    let entry: LiveEntry
    var body: some View {
        HStack(spacing: 10) {
            RoundFlag(asset: entry.asset, size: 22)
            Text(entry.name).font(.system(size: 13.5)).lineLimit(1)
            Spacer(minLength: 4)
            Text(CountryNames.groups(entry.groups)).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.38)).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
    }
}

/// The banner as a button, with the same hover ring as the Films banners.
private struct PinnedButton: View {
    let entry: LiveEntry
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            PinnedBanner(entry: entry)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(hover ? 0.5 : 0.06), lineWidth: hover ? 2 : 1))
                .scaleEffect(hover ? 1.01 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
