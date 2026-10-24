import SwiftUI

// Apple TV Live (design A): pinned countries as big flag cards, regions as gradient cards, then every country A to Z.

struct LiveLandingTV: View {
    let open: (String) -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings

    var body: some View {
        let dir = LiveDirectory(catalog: catalog, pinned: settings.countries)
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 34) {
                Text("Live").font(.ui(48, .bold)).padding(.horizontal, Theme.x0)
                if !dir.pinned.isEmpty {
                    section("Pinned", "your countries · change in Settings")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 2), alignment: .leading, spacing: 28) {
                        ForEach(dir.pinned) { c in
                            Button { open(c.code) } label: { PinnedBanner(entry: c, k: 1.6) }
                                .buttonStyle(TileButtonStyle(radius: 12 * 1.6, scale: 1.06, lift: 6))
                                .accessibilityIdentifier("live:pinned:" + c.code)
                        }
                    }
                    .padding(.horizontal, Theme.x0).padding(.vertical, 12).focusSection()
                }
                if !dir.regions.isEmpty {
                    section("Regions", "\(dir.regions.count)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 26) {
                            ForEach(dir.regions) { r in
                                Button { open(r.code) } label: { regionCard(r) }
                                    .buttonStyle(TileButtonStyle(radius: 24, scale: 1.06, lift: 6))
                                    .accessibilityIdentifier("live:region:" + r.region.id)
                            }
                        }
                        .padding(.horizontal, Theme.x0).padding(.vertical, 20)
                    }
                    .scrollClipDisabled().focusSection()
                }
                if !dir.all.isEmpty {
                    section("All countries", "\(dir.all.count) · A to Z")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 4), alignment: .leading, spacing: 18) {
                        ForEach(dir.all) { c in
                            Button { open(c.code) } label: { chip(c) }
                                .buttonStyle(TileButtonStyle(radius: 18, scale: 1.05, lift: 4))
                                .accessibilityIdentifier("live:country:" + c.code)
                        }
                    }
                    .padding(.horizontal, Theme.x0).focusSection()
                }
            }
            .padding(.top, 110).padding(.bottom, 80)
        }
        .frame(width: 1920, height: 1080)
        .task { await catalog.ensureLiveIndex() }
    }

    private func section(_ title: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.ui(34, .bold))
            Text(note).font(.ui(24)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, Theme.x0)
    }

    private func regionCard(_ r: LiveRegionEntry) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [r.region.from.opacity(0.8), r.region.to.opacity(0.67)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "globe").font(.system(size: 130, weight: .light)).opacity(0.28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 24, y: -14)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text(r.region.title).font(.ui(27, .bold)).lineLimit(1)
                Text(CountryNames.groups(r.groups)).font(.ui(20)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: 320, height: 170)
    }

    private func chip(_ c: LiveEntry) -> some View {
        HStack(spacing: 14) {
            RoundFlag(asset: c.asset, size: 38)
            Text(c.name).font(.ui(24)).lineLimit(1)
            Spacer(minLength: 6)
            Text(CountryNames.groups(c.groups)).font(.ui(19)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        .padding(.horizontal, 20).frame(height: 72)
        .background(Color.white.opacity(0.07))
    }
}
