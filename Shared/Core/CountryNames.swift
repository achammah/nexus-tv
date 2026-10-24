import SwiftUI

/// Provider country codes -> full name and ISO flag, and the directory behind the Live page
/// (pinned countries, regions, all countries A to Z). Shared by the Mac and the Apple TV app.
enum CountryNames {
    /// Provider code -> ISO 3166 code, where the provider does not use the ISO one.
    private static let iso: [String: String] = [
        "UK": "GB", "AFG": "AF", "VT": "VN", "KO": "XK", "EST": "EE", "BH": "BA", "CG": "ME", "KA": "KZ",
        "UKR": "UA", "BAN": "BD", "SL": "SI", "IS": "IL",
    ]
    /// Names that differ from the system's English name.
    private static let override: [String: String] = [
        "GB": "United Kingdom", "TR": "Türkiye", "HK": "Hong Kong", "BA": "Bosnia", "MK": "North Macedonia", "CZ": "Czechia",
        "US": "United States", "XK": "Kosovo", "VN": "Vietnam", "RU": "Russia", "IR": "Iran", "ME": "Montenegro",
    ]
    /// Groups that are not a country: (provider codes, title, gradient from, to).
    struct Region: Identifiable {
        let id: String, codes: [String], title: String, from: Color, to: Color
    }
    static let regions: [Region] = [
        Region(id: "AR", codes: ["AR"], title: "Arabic", from: Color(hex: 0xC9A227), to: Color(hex: 0x1F6F5C)),
        Region(id: "ASIA", codes: ["ASIA"], title: "Asia", from: Color(hex: 0xE0475B), to: Color(hex: 0xF2B33D)),
        Region(id: "LAT", codes: ["LAT", "LA"], title: "Latin America", from: Color(hex: 0x2BA84A), to: Color(hex: 0xF2C94C)),
        Region(id: "BEE", codes: ["BEE"], title: "beIN & Arabic sports", from: Color(hex: 0x6A2C91), to: Color(hex: 0xC2185B)),
        Region(id: "EXYU", codes: ["EXYU"], title: "Ex-Yugoslavia", from: Color(hex: 0x1E4FA0), to: Color(hex: 0xD52B1E)),
        Region(id: "AFR", codes: ["AFR"], title: "Africa", from: Color(hex: 0xE2A33B), to: Color(hex: 0x2E7D32)),
        Region(id: "CRB", codes: ["CRB"], title: "Caribbean", from: Color(hex: 0x00A3E0), to: Color(hex: 0xFFD100)),
        Region(id: "KU", codes: ["KU"], title: "Kurdish", from: Color(hex: 0xD32F2F), to: Color(hex: 0x2E7D32)),
        Region(id: "EU", codes: ["EU"], title: "Europe", from: Color(hex: 0x1F3A93), to: Color(hex: 0xFFCC00)),
        Region(id: "NA", codes: ["NA"], title: "North Africa", from: Color(hex: 0xC62828), to: Color(hex: 0x1B5E20)),
    ]
    private static let regionCodes: Set<String> = Set(regions.flatMap(\.codes))
    static func isRegion(_ cc: String) -> Bool { regionCodes.contains(cc) }

    private static let english = Locale(identifier: "en_US")
    private static func isoCode(_ cc: String) -> String? {
        if isRegion(cc) { return nil }
        let c = iso[cc] ?? cc
        guard c.count == 2, english.localizedString(forRegionCode: c) != nil else { return nil }
        return c
    }

    /// ISO codes that have a round flag in Shared/Brand.xcassets ("flag-<iso>", circle-flags, MIT).
    private static let flagCodes: Set<String> = Set("ac ad ae af ag ai al am an ao aq ar as at au aw ax az ba bb bd be bf bg bh bi bj bl bm bn bo bq br bs bt bv bw by bz ca cc cd cf cg ch ci ck cl cm cn co cp cq cr cu cv cw cx cy cz de dg dj dk dm do dz ea ec ee eg eh er es et eu fi fj fk fm fo fr fx ga gb gd ge gf gg gh gi gl gm gn gp gq gr gs gt gu gw gy hk hm hn hr ht hu ic id ie il im in io iq ir is it je jm jo jp ke kg kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md me mf mg mh mk ml mm mn mo mp mq mr ms mt mu mv mw mx my mz na nc ne nf ng ni nl no np nr nu nz om pa pe pf pg ph pk pl pm pn pr ps pt pw py qa re ro rs ru rw sa sb sc sd se sg sh si sj sk sl sm sn so sr ss st su sv sx sy sz ta tc td tf tg th tj tk tl tm tn to tr tt tv tw tz ua ug uk um un us uy uz va vc ve vg vi vn vu wf ws xk xx ye yt yu za zm zw".split(separator: " ").map(String.init))
    /// Asset name of the round flag ("UK" -> "flag-gb"); nil for a region or a code with no flag.
    static func flagAsset(_ cc: String) -> String? {
        guard let c = isoCode(cc)?.lowercased(), flagCodes.contains(c) else { return nil }
        return "flag-" + c
    }
    /// The main colour of a flag, for the wash on a pinned card.
    static func flagColor(_ cc: String) -> Color {
        Color(hex: mainColour[isoCode(cc) ?? ""] ?? 0x2A3350)
    }
    private static let mainColour: [String: UInt32] = [
        "BE": 0x3A3000, "FR": 0x0A1A4A, "GB": 0x4A0A14, "US": 0x0E1A40, "ES": 0x5A1010, "DE": 0x2A2A2A, "NL": 0x4A1A10, "CA": 0x5A0F14,
        "IT": 0x0F4A24, "PL": 0x4A1018, "PT": 0x0F4A24, "TR": 0x6A0F18, "CZ": 0x0E2A5A, "BR": 0x0F4A24, "GR": 0x0E3A6A, "IL": 0x0E3A6A,
        "RO": 0x0E2A5A, "IR": 0x0F4A24, "AU": 0x0A1E4A, "AT": 0x5A0F14, "AL": 0x5A0F14, "CH": 0x5A0F14, "ME": 0x5A1010, "ID": 0x5A0F14,
        "HR": 0x0E2A5A, "NZ": 0x0A1E4A, "RS": 0x4A1020, "HU": 0x0F4A24, "SK": 0x0E2A5A, "BG": 0x0F4A24, "BA": 0x0E2A5A, "SG": 0x5A0F14,
        "CY": 0x3A3A3A, "SI": 0x0E2A5A, "MK": 0x5A1010, "MY": 0x0E2A5A, "RU": 0x0E2A5A, "BD": 0x0F4A24, "AZ": 0x0E3A6A, "AF": 0x1A1A1A,
        "AM": 0x5A1010, "UA": 0x0E3A6A, "TH": 0x0E2A5A, "NP": 0x5A0F14, "KZ": 0x0E4A6A, "HK": 0x5A0F14, "JP": 0x3A3A3A, "UZ": 0x0E4A6A,
        "VN": 0x5A0F14, "MU": 0x4A1020, "PH": 0x0E2A5A, "MT": 0x5A0F14, "XK": 0x0E2A5A, "EE": 0x0E3A6A, "GE": 0x4A1020, "FI": 0x0E2A5A,
        "SE": 0x0E3A6A, "IE": 0x0F4A24, "IN": 0x5A3A0F, "PK": 0x0F4A24, "BY": 0x4A1020, "LT": 0x3A3A0A,
    ]

    /// Full name; a region keeps its group title; an unknown code stays as the provider wrote it.
    static func name(_ cc: String) -> String {
        if let r = regions.first(where: { $0.codes.contains(cc) }) { return r.title }
        guard let c = isoCode(cc) else { return cc }
        return override[c] ?? english.localizedString(forRegionCode: c) ?? cc
    }
    static func groups(_ n: Int) -> String { n == 1 ? "1 group" : "\(n) groups" }
    static func channels(_ n: Int) -> String { n == 1 ? "1 channel" : "\(n.formatted(.number)) channels" }
}

/// One card of the Live page.
struct LiveEntry: Identifiable {
    let code: String            // provider code the country page opens with
    let name: String
    let asset: String?          // round flag in the asset catalogue
    let color: Color            // main colour of the flag
    let logos: [String]         // first channel logos (pinned cards only)
    let groups: Int
    let channels: Int?          // nil until the whole live list is loaded
    var id: String { code }
    var detail: String { (channels.map { CountryNames.channels($0) + " · " } ?? "") + CountryNames.groups(groups) }
}

struct LiveRegionEntry: Identifiable {
    let region: CountryNames.Region
    let code: String            // first code with groups
    let groups: Int
    var id: String { region.id }
}

struct LiveDirectory {
    let pinned: [LiveEntry], regions: [LiveRegionEntry], all: [LiveEntry]

    @MainActor init(catalog: Catalog, pinned codes: [String]) {
        var groupCount: [String: Int] = [:]
        for (cc, n) in catalog.liveCountries { groupCount[cc] = n }
        func channels(_ cc: String) -> Int? {
            guard !catalog.liveIndex.isEmpty else { return nil }
            return catalog.liveGroups(cc).reduce(0) { $0 + (catalog.liveIndex[$1.id]?.count ?? 0) }
        }
        func logos(_ cc: String) -> [String] {
            guard codes.contains(cc), !catalog.liveIndex.isEmpty else { return [] }
            var out: [String] = []
            for g in catalog.liveGroups(cc) {
                for ch in catalog.liveIndex[g.id] ?? [] where !ch.icon.isEmpty && out.count < 16 && !out.contains(ch.icon) { out.append(ch.icon) }
                if out.count >= 16 { break }
            }
            return out
        }
        func entry(_ cc: String) -> LiveEntry {
            LiveEntry(code: cc, name: CountryNames.name(cc), asset: CountryNames.flagAsset(cc), color: CountryNames.flagColor(cc), logos: logos(cc), groups: groupCount[cc] ?? 0, channels: channels(cc))
        }
        pinned = codes.filter { !CountryNames.isRegion($0) }.map(entry)
        regions = CountryNames.regions.compactMap { r in
            let n = r.codes.reduce(0) { $0 + (groupCount[$1] ?? 0) }
            guard n > 0 else { return nil }
            return LiveRegionEntry(region: r, code: r.codes.first { (groupCount[$0] ?? 0) > 0 } ?? r.codes[0], groups: n)
        }
        all = groupCount.keys.filter { !CountryNames.isRegion($0) && !codes.contains($0) }.map(entry)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// A round flag with a small shadow.
struct RoundFlag: View {
    let asset: String?
    var size: CGFloat = 20
    var body: some View {
        if let asset {
            Image(asset).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).clipShape(Circle())
                .shadow(color: .black.opacity(0.45), radius: size * 0.08, y: size * 0.04)
        }
    }
}
