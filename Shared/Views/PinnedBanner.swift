import SwiftUI

/// A pinned country on the Live page: a Films-style banner, 120 pt tall at k = 1, full width of its column.
/// Background: a mosaic of the country's channel logos; over it the flag's main colour from the left and a bottom shade;
/// bottom left: the round flag, a small line with counts, the name.
struct PinnedBanner: View {
    let entry: LiveEntry
    var k: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255)
            mosaic
            LinearGradient(stops: [.init(color: entry.color.opacity(0.94), location: 0), .init(color: entry.color.opacity(0.63), location: 0.3),
                                   .init(color: .clear, location: 0.7)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.6), location: 1)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 12 * k) {
                RoundFlag(asset: entry.asset, size: 38 * k)
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text(entry.detail.uppercased()).font(.system(size: 11 * k, weight: .bold)).tracking(0.9 * k)
                        .foregroundStyle(Color.white.opacity(0.72)).lineLimit(1)
                    Text(entry.name).font(.system(size: 20 * k, weight: .heavy)).tracking(-0.2 * k).lineLimit(1)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 4 * k, y: k)
                }
            }
            .padding(.leading, 18 * k).padding(.bottom, 16 * k)
        }
        .frame(maxWidth: .infinity, minHeight: 120 * k, maxHeight: 120 * k)
        .clipShape(RoundedRectangle(cornerRadius: 16 * k, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16 * k, style: .continuous))
    }

    /// 8 x 2 small rounded tiles, tilted -3 degrees; an empty tile when the country has fewer than 16 logos.
    private var mosaic: some View {
        VStack(spacing: 6 * k) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6 * k) {
                    ForEach(0..<8, id: \.self) { col in
                        let i = row * 8 + col
                        RoundedRectangle(cornerRadius: 8 * k, style: .continuous).fill(Color.white.opacity(0.07))
                            .overlay {
                                if i < entry.logos.count { ArtImage(url: Img.url(entry.logos[i], .poster), fill: false).padding(8 * k) }
                            }
                    }
                }
            }
        }
        .padding(6 * k)
        .scaleEffect(1.15).rotationEffect(.degrees(-3)).opacity(0.8)
    }
}
