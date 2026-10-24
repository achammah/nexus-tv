import Foundation

/// A list or a family opened from a browse page: which provider ids, which family or service key, its title.
struct BrowseRef: Hashable {
    var kind: ItemKind
    var ids: [String] = []
    var key: String = ""
    var title: String
    var cc: String = ""
}

/// Browse rules for the long lists (owner-approved layout 2a "shelves by family", card 3b "cinematic banner"),
/// ported from mac-design/browse/shared/browse.js: clean names, families, the small-list rule, services, live merges.
enum Browse {
    /// A film or series list under this many titles is hidden behind "Show N small lists".
    static let minTitles = 20
    /// A live list under this many channels is hidden the same way.
    static let minChannels = 8
    private static let junk = try! NSRegularExpression(pattern: "CAM|PRE-RELEASE")

    // MARK: clean names

    private static let acronyms: Set<String> = ["4K", "3D", "UHD", "HD", "FHD", "HEVC", "UK", "US", "TV", "HBO", "BET", "NBC", "CBS", "ABC", "FX", "AMC", "MGM", "DC", "SF", "EPL", "F1", "PPV", "UFC", "NBA", "WNBA", "NFL", "MLB", "MILB", "NHL", "ESPN", "DAZN", "BBC", "BBCI", "ITV", "VIP", "MLS", "GAA", "PBS", "CW", "TT", "PDC", "FA", "MXGP", "NCAAF", "NCAAB", "NFHS", "B1G", "BTN", "FIFA", "MC", "TNT", "PSF", "RTL"]
    private static let overrides: [String: String] = [
        "TOP IMDB/OSCAR MOVIES": "IMDb top & Oscar winners", "FRENCH MOVIES / ENG SUB": "French, English subtitles",
        "ITALIAN MOVIES / ENG SUB": "Italian, English subtitles", "NEW RELEASED": "New releases",
        "4K DOCUMENTARY/MUSIC/ STAND-UP": "Documentary, music & stand-up", "SCIENCE FICTION/FANTASTY": "Sci-fi & fantasy",
        "MOVIES 2018-2021": "2018 to 2021", "SCIENCE/FICTION/FANTASTIQUE": "Science-fiction & fantastique",
        "DE NOËL": "Films de Noël", "FILM 1980-1999": "1980 à 1999", "ART MARTIAUX": "Arts martiaux",
        "4K MOVIES": "All 4K films", "UK MOVIES": "British films", "APPLE+ MOVIES": "Apple TV+ films",
        "APPLE+ KIDS": "Apple TV+ Kids", "PRIME+": "Prime Video", "PRIME +": "Prime Video", "MYCANAL": "myCanal",
        "NETFLIX": "Netflix", "DISNEY+": "Disney+", "CLASSIC MOVIES COLLECTION": "Classic films",
        "ACTORS & DIRECTORS": "Actors & directors", "FILMOGRAPHIE LOUIS DE FUNES": "Louis de Funès",
        "FILMS UHD": "Films UHD", "FILMS 4K/3D": "Films 4K & 3D", "JEUNESSE 4K/3D": "Jeunesse 4K & 3D",
        "BET/ALLBLK MOVIES": "BET & ALLBLK", "HALLMARK MOVIES": "Hallmark", "WORLDCUP 2022": "World Cup 2022",
        "RATED R": "Rated R", "HORREUR/EPOUVANTE": "Horreur & épouvante", "TV MOVIES": "TV films",
        "ADVENTURE MOVIES": "Adventure", "CHRISTMAS MOVIES": "Christmas", "FOREIGN MOVIES": "World cinema",
        "PIXAR MOVIES": "Pixar", "COMÉDIE/DRAME": "Comédie & drame", "HBO MAX": "HBO Max", "HBO FILMS": "HBO films",
        "APPLE TV+": "Apple TV+", "PARAMOUNT+": "Paramount+", "ZIGGO GO": "Ziggo GO",
        // live
        "GENERAL": "General", "EPL PREMIER LEAGUE": "Premier League", "NOW TV": "NOW TV", "BBCI": "BBC iPlayer",
        "NEWS NETWORK": "News", "KIDS NETWORK": "Kids", "SPORTS NETWORK": "Sports", "MOVIES NETWORK": "Movies",
        "TV": "Local TV", "FLO NETWORK": "FloSports", "PRIME": "Prime Video channels", "TUBI": "Tubi",
        "PLUTO TV": "Pluto TV", "NETFLIX ON AIR": "Netflix on air", "CINEMANIA HOLLYWOOD": "Cinemania Hollywood",
        "CINEMANIA TV SHOWS": "Cinemania TV shows", "SPECTRUM NETWORK": "Spectrum", "TELEMUNDO NETWORK": "Telemundo",
        "VIX+ DEPORTES": "ViX+ Deportes", "CW/MY NETWORK": "CW & MyNetwork", "ESPN PLUS": "ESPN+", "ESPN PLAY": "ESPN Play",
        "HBO MAX NETWORK": "HBO Max", "MLS NETWORK": "MLS", "TENNIS CHANNEL PLUS": "Tennis Channel Plus",
        "THEATRE ET SPECTACLE": "Théâtre & spectacle", "BBCIPLAYER SERIES": "BBC iPlayer series", "FORMULA 1 + MOTOGP": "Formula 1 & MotoGP",
        "24/7 MOVIES & SERIES": "24/7 films & series", "ACTEURS FRANÇAIS": "Acteurs français", "MAFIA GANGSTER": "Mafia & gangster",
        "MAX ESPN /": "Max & ESPN", "NETFLIX JEUNESSE FAMILLE": "Netflix jeunesse & famille", "CHILDREN/FAMILY": "Children & family",
        "STAND-UP COMEDY": "Stand-up comedy", "DRAMA/COMEDY": "Drama & comedy", "DRAMA/ROMANCE": "Drama & romance", "DRAMA/CRIME": "Drama & crime",
        "ACTION/THRILLER": "Action & thriller", "HORROR/THRILLER": "Horror & thriller", "MUSIC/CONCERTS": "Music & concerts",
        "BIBLICAL/RELIGIOUS": "Biblical & religious", "GANGSTER & MAFIA": "Gangster & mafia", "CLASSIC CARTOONS": "Classic cartoons",
        "4K CHILDREN": "4K children", "4K CLASSIC MOVIES": "4K classics", "4K MAFIA & GANGSTER": "4K mafia & gangster", "4K NETFLIX MOVIES": "4K Netflix",
        "MYCANAL/TF1+": "myCanal & TF1+", "ANCIENNE": "Séries anciennes", "EMISSION | TÉLÉ-RÉALITÉ": "Émissions & télé-réalité",
        "NETFLIX CRIME | MYSTERE": "Netflix crime & mystère", "BET/ALLBLK SERIES": "BET & ALLBLK series", "AMAZON PRIME": "Prime Video",
        "TURKISH SERIES SUB": "Turkish series, subtitled", "PRE-RELEASES/SD CAM": "Pre-releases (cam copies)",
    ]
    private static let brands: Set<String> = ["NETFLIX", "DISNEY", "DISNEY+", "APPLE", "PRIME", "HULU", "FOX", "FOX+", "MARVEL", "PIXAR", "HALLMARK", "PEACOCK", "STARZ", "SHOWTIME", "PARAMOUNT+", "ASIA", "ENGLISH", "FRENCH", "TURKISH", "ASIAN", "ITALIAN", "SKY", "STORE", "DISCOVERY", "DISCOVERY+", "NOW", "TUBI", "PLUTO", "SKYMIX", "EUROSPORT", "PREMIER", "LEAGUE", "CHAMPIONSHIP", "SCOTTISH", "NATIONAL", "CYMRU", "ULSTER", "VIAPLAY", "MATCHROOM", "MONOMAX", "VIDIO", "MOLA", "HUB", "RALLY", "SERIE", "LIGA", "LIGUE", "UNIVERSE", "UNIVERS", "CHRISTMAS", "NOËL", "AMAZON", "TELEMUNDO", "SPECTRUM", "CINEMANIA", "HOLLYWOOD", "ALLBLK", "MOTOGP", "FORMULA", "DAZN", "SAGA", "PLAY", "GO", "VIDEO"]

    /// The provider's name without its language or country tag, upper case: the key every rule matches on.
    static func raw(_ providerName: String) -> String { Clean.category(providerName).uppercased() }

    /// "SCIENCE FICTION/FANTASTY" -> "Sci-fi & fantasy"; "|EN| NETFLIX MOVIES" -> "Netflix"; no " · EN".
    static func label(_ raw: String) -> String {
        if let o = overrides[raw] { return o }
        var s = raw.replacingOccurrences(of: "\\s*/\\s*", with: " & ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\|\\s*", with: " & ", options: .regularExpression)
            .replacingOccurrences(of: "APPLE+", with: "APPLE TV+")
            .replacingOccurrences(of: "\\s+(MOVIES|FILMS)$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+NETWORK$", with: "", options: .regularExpression)
        let words = s.split(separator: " ").enumerated().map { i, w -> String in
            let word = String(w)
            if acronyms.contains(word.replacingOccurrences(of: "[+:]", with: "", options: .regularExpression)) { return word }
            if i == 0 || brands.contains(word) { return word.prefix(1) + word.dropFirst().lowercased() }
            return word.lowercased()
        }
        s = words.joined(separator: " ").replacingOccurrences(of: "\\bAnd\\b", with: "&", options: .regularExpression)
            .replacingOccurrences(of: " \\+$", with: "+", options: .regularExpression)
            .replacingOccurrences(of: "\\s*&\\s*$", with: "", options: .regularExpression)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// A label shown inside its service ("Netflix kids" inside Netflix -> "Kids").
    static func inService(_ label: String, _ service: String) -> String {
        let r = label.replacingOccurrences(of: "^" + NSRegularExpression.escapedPattern(for: service) + "\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "All" : r.prefix(1).uppercased() + r.dropFirst()
    }

    /// Names of a service's lists shown inside it ("Kids"); two lists with one name are told apart by language
    /// ("All", "All in English").
    static func serviceLabels(_ lists: [List], _ service: String) -> [String] {
        let base = lists.map { inService($0.label, service) }
        return base.enumerated().map { i, b in
            guard base.filter({ $0 == b }).count > 1, base.firstIndex(of: b) != i else { return b }
            let l = ["EN": "in English", "FR": "en français", "MULTI": "multi-language"][lists[i].lang] ?? "(\(i + 1))"
            return b + " " + l
        }
    }

    // MARK: services and families (films, series)

    struct Service: Hashable {
        let name: String
        let rule: NSRegularExpression
        /// Public logo (github.com/tv-logo/tv-logos), nil = the name on the card.
        let logo: String?
        /// A dark logo: it sits on a light plate.
        let dark: Bool
        static func == (a: Service, b: Service) -> Bool { a.name == b.name }
        func hash(into h: inout Hasher) { h.combine(name) }
    }
    static let logoBase = "https://raw.githubusercontent.com/tv-logo/tv-logos/main/"
    private static func svc(_ n: String, _ r: String, _ l: String?, dark: Bool = false, ci: Bool = false) -> Service {
        Service(name: n, rule: try! NSRegularExpression(pattern: r, options: ci ? .caseInsensitive : []), logo: l.map { logoBase + $0 }, dark: dark)
    }
    static let services: [Service] = [
        svc("Netflix", "NETFLIX", "misc/media/netflix.png"), svc("Disney+", "DISNEY", "misc/media/disney-plus.png"),
        svc("Apple TV+", "APPLE", "misc/media/apple-tv-plus.png"), svc("Prime Video", "PRIME", "misc/media/prime-video.png"),
        svc("HBO Max", "HBO", "misc/media/hbo-max.png"), svc("Hulu", "HULU", "misc/media/hulu.png"),
        svc("Paramount+", "PARAMOUNT|CBS", "misc/media/paramount-plus.png"), svc("myCanal", "CANAL|TF1", "countries/france/canal-plus-fr.png", ci: true),
        svc("Peacock", "PEACOCK|NBC", "misc/media/peacock.png"), svc("Showtime & Starz", "SHOWTIME|STARZ", "countries/united-states/showtime-us.png", dark: true),
        svc("AMC+", "AMC", "misc/vod/amc-plus-vod-us.png"), svc("Fox", "FOX\\+", nil), svc("Ziggo GO", "ZIGGO", nil),
        svc("BET & ALLBLK", "BET/ALLBLK", "countries/united-states/bet-us.png"), svc("Hallmark", "HALLMARK", "countries/united-states/hallmark-channel-us.png"),
    ]
    private static let anyService = try! NSRegularExpression(pattern: services.map(\.rule.pattern).joined(separator: "|"), options: .caseInsensitive)

    /// The six film and series families, in the order the page shows them (the first matching rule wins:
    /// 4K, kids, services, world, collections, then genres for everything else).
    enum Family: String, CaseIterable, Hashable {
        case services, genres, uhd, kids, world, collections
        var name: String {
            switch self {
            case .services: "Streaming services"; case .genres: "Genres"; case .uhd: "4K & UHD"
            case .kids: "Kids & family"; case .world: "World & languages"; case .collections: "Collections & eras"
            }
        }
    }
    private static let familyRules: [(Family, NSRegularExpression)] = [
        (.uhd, try! NSRegularExpression(pattern: "4K|UHD|3D")),
        (.kids, try! NSRegularExpression(pattern: "KIDS|CHILDREN|FAMILY|JEUNESSE|CARTOON|ANIMATION|PIXAR|ENFANT")),
        (.services, anyService),
        (.world, try! NSRegularExpression(pattern: "FRENCH|ITALIAN|UK MOVIES|FOREIGN|ASIATIQUE|TURKISH|ACTEURS FRAN|ENGLISH SERIES|UK SERIES|ASIAN SERIES")),
        (.collections, try! NSRegularExpression(pattern: "TOP|NEW|20\\d\\d|19\\d\\d|CLASSI|COLLECTION|ACTORS|SAGA|CHRISTMAS|NOËL|MARVEL|CHUCK|FUNES|WORLDCUP|RATED|TV MOVIES|LATEST|GOLDEN")),
    ]
    static func hit(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    /// One provider list as the browse pages show it.
    struct List: Hashable, Identifiable {
        /// Provider category ids (a live list can merge its quality copies).
        let ids: [String]
        let raw: String
        let label: String
        /// Titles or channels; nil while the counts are not loaded (such a list is never hidden).
        let count: Int?
        let family: String
        let service: String?
        let hidden: Bool
        /// Events and pay-per-view: last and dimmed.
        var muted = false
        /// The provider's language tag ("EN", "FR", "" when shared).
        var lang = ""
        var id: String { ids.joined(separator: "+") }
    }

    struct Shelf: Hashable, Identifiable {
        let key: String, name: String
        let lists: [List]
        var id: String { key }
    }

    struct Library {
        /// Families in page order, each with its lists, biggest first; the Streaming services shelf is built from `services`.
        let shelves: [Shelf]
        let services: [(service: Service, lists: [List])]
        let hidden: [List]
        let visibleCount: Int
    }

    /// Page language: English shows EN, multi-language and untagged lists; Français shows FR and the same shared ones.
    static func inLanguage(_ providerName: String, _ lang: String) -> Bool {
        let t = Clean.tag(providerName) ?? ""
        return t == lang || t == "" || t == "MULTI"
    }

    static func library(_ cats: [XCategory], counts: [String: Int], language: String) -> Library {
        let adult = { (n: String) in n.localizedCaseInsensitiveContains("ADULT") || n.contains("XXX") || n.contains("18+") }
        let all: [List] = cats.filter { inLanguage($0.name, language) && !adult($0.name) }.map { c in
            let r = raw(c.name), n = counts[c.id]
            let fam = familyRules.first { hit($0.1, r) }?.0 ?? .genres
            let s = services.first { hit($0.rule, r) }
            return List(ids: [c.id], raw: r, label: label(r), count: n, family: fam.rawValue, service: s?.name,
                        hidden: (n.map { $0 < minTitles } ?? false) || hit(junk, r), lang: Clean.tag(c.name) ?? "")
        }
        let vis = all.filter { !$0.hidden }
        let big = { (a: List, b: List) in (a.count ?? 0) > (b.count ?? 0) }
        let svcs = services.map { s in (s, vis.filter { $0.service == s.name }.sorted(by: big)) }.filter { !$0.1.isEmpty }
        let order: [Family] = [.services, .genres, .uhd, .kids, .world, .collections]
        let shelves = order.compactMap { f -> Shelf? in
            if f == .services { return svcs.isEmpty ? nil : Shelf(key: f.rawValue, name: f.name, lists: []) }
            let l = vis.filter { $0.family == f.rawValue }.sorted(by: big)
            return l.isEmpty ? nil : Shelf(key: f.rawValue, name: f.name, lists: l)
        }
        return Library(shelves: shelves, services: svcs.map { ($0.0, $0.1) }, hidden: all.filter(\.hidden), visibleCount: vis.count)
    }

    // MARK: live

    private static let quality = try! NSRegularExpression(pattern: "\\s+(HEVC|FHD|HD|LQ|4K|UHD)$")
    enum LiveFamily: String, CaseIterable {
        case main, sport, news, movies, kids, doc, music, reg, ev
        var name: String {
            switch self {
            case .main: "Main channels"; case .sport: "Sports"; case .news: "News"; case .movies: "Films & series"; case .kids: "Kids"
            case .doc: "Documentary"; case .music: "Music"; case .reg: "Regional"; case .ev: "Events & pay-per-view"
            }
        }
    }
    private static let liveRules: [(LiveFamily, NSRegularExpression)] = [
        (.ev, try! NSRegularExpression(pattern: "PPV|EVENT|PAY PER VIEW|PACKAGE|VIP|RED BUTTON|ⱽ")),
        (.sport, try! NSRegularExpression(pattern: "SPORT|LEAGUE|FOOTBALL|EPL|CHAMPIONSHIP|CUP|F1|FORMULA|EUROSPORT|NBA|NFL|MLB|NHL|NCAA|ESPN|DAZN|TENNIS|MLS|LIGUE|RUGBY|GAA|FLO|SOCCER|BEIN|EQUIPE|DEPORTES")),
        (.news, try! NSRegularExpression(pattern: "NEWS")),
        (.kids, try! NSRegularExpression(pattern: "KIDS|KINDEREN|ENFANTS")),
        (.doc, try! NSRegularExpression(pattern: "DOC|DISCOVERY")),
        (.movies, try! NSRegularExpression(pattern: "MOVIE|CINE|SERIES|NETFLIX|SKY STORE|24/7|SKYMIX|APPLE TV|TUBI|PLUTO|REALITY|^PRIME|AMAZON PRIME")),
        (.music, try! NSRegularExpression(pattern: "MUSIC|MC VIDEO")),
        (.reg, try! NSRegularExpression(pattern: "WALLONIË|CARIBBEAN|SPECTRUM|TELEMUNDO|TELESAT")),
    ]

    struct Live {
        let shelves: [Shelf]
        let hidden: [List]
        let channels: Int
        let providerLists: Int
    }

    /// One country's live groups: quality copies merged into one list ("General" + "General HEVC"), nine families,
    /// lists under `minChannels` hidden, events and pay-per-view last and dimmed.
    static func live(_ groups: [XCategory], counts: [String: Int]) -> Live {
        var merged: [(raw: String, ids: [String], n: Int?)] = []
        let raws = Set(groups.map { raw($0.name) })
        for g in groups {
            let r = raw(g.name)
            let base = hit(quality, r) ? r.replacingOccurrences(of: quality.pattern, with: "", options: .regularExpression) : r
            let key = raws.contains(base) ? base : r
            let n = counts[g.id]
            if let i = merged.firstIndex(where: { $0.raw == key }) {
                merged[i].ids.append(g.id)
                if let n { merged[i].n = (merged[i].n ?? 0) + n }
            } else { merged.append((key, [g.id], n)) }
        }
        let all = merged.map { m -> List in
            let fam = liveRules.first { hit($0.1, m.raw) }?.0 ?? .main
            return List(ids: m.ids, raw: m.raw, label: label(m.raw), count: m.n, family: fam.rawValue, service: nil,
                        hidden: m.n.map { $0 < minChannels } ?? false, muted: fam == .ev)
        }
        let vis = all.filter { !$0.hidden }
        var shelves = LiveFamily.allCases.compactMap { f -> Shelf? in
            let l = vis.filter { $0.family == f.rawValue }.sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            return l.isEmpty ? nil : Shelf(key: f.rawValue, name: f.name, lists: l)
        }
        // families of one list share one shelf ("News, kids & regional"), where the first of them stood
        let single = shelves.filter { $0.lists.count == 1 && $0.key != LiveFamily.main.rawValue && $0.key != LiveFamily.ev.rawValue }
        if single.count >= 2, let at = shelves.firstIndex(of: single[0]) {
            let names = single.map(\.name)
            let joined = names.dropLast().enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: ", ")
                + " & " + names.last!.lowercased()
            let merged = Shelf(key: "mixed", name: joined, lists: single.flatMap(\.lists))
            shelves.removeAll { single.contains($0) }
            shelves.insert(merged, at: min(at, shelves.count))
        }
        return Live(shelves: shelves, hidden: all.filter(\.hidden), channels: groups.reduce(0) { $0 + (counts[$1.id] ?? 0) }, providerLists: groups.count)
    }

    /// Public network logos for live list cards, by clean list name.
    static let liveLogos: [String: String] = [
        "NBC": "countries/united-states/nbc-us.png", "Fox": "countries/united-states/fox-us.png", "CBS": "countries/united-states/cbs-logo-white-us.png",
        "ABC": "countries/united-states/abc-us.png", "PBS": "countries/united-states/pbs-us.png", "CW & MyNetwork": "countries/united-states/the-cw-us.png",
        "ESPN+": "misc/media/espn-plus.png", "FloSports": "misc/media/flosports.png", "Tubi": "misc/media/tubi.png", "Pluto TV": "misc/media/pluto-tv.png",
        "Telemundo": "countries/united-states/telemundo-us.png", "Tennis Channel Plus": "countries/united-states/tennis-channel-us.png",
        "Hulu": "misc/media/hulu.png", "HBO Max": "misc/media/hbo-max.png", "Disney+": "misc/media/disney-plus.png", "Peacock": "misc/media/peacock.png",
        "Paramount+": "misc/media/paramount-plus.png", "Netflix on air": "misc/media/netflix.png", "Prime Video channels": "misc/media/prime-video.png",
    ].mapValues { logoBase + $0 }

    /// "1,389 films", "1 film", "247 series", "5 lists".
    static func count(_ n: Int, _ unit: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        return (f.string(from: NSNumber(value: n)) ?? "\(n)") + " " + unit + (n == 1 || unit == "series" ? "" : "s")
    }
}
