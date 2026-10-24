import Foundation

/// Search matching shared by the Apple TV and Mac apps: names that start with the text first, then a word start,
/// then anywhere; chosen countries and languages first, then every other country and language (with a badge).
enum SearchEngine {
    /// One matching pass off the main thread: names that start with the text first, then a word start, then anywhere.
    nonisolated static func match(_ needle: String, groups: [(String, [XCategory])], live: [String: [Channel]], films: [IndexEntry], series: [IndexEntry],
                                  extra: [MediaItem], other: [MoreEntry], otherLive: [String: String], maxHits: Int) async -> [[MediaItem]] {
        do {
            return await Task.detached(priority: .userInitiated) { () -> [[MediaItem]] in
                func score(_ name: String) -> Int? {
                    let n = name.lowercased()
                    guard let range = n.range(of: needle) else { return nil }
                    if range.lowerBound == n.startIndex { return 0 }
                    let prev = n[n.index(before: range.lowerBound)]
                    return " -:(".contains(prev) ? 1 : 2
                }
                func best<T>(_ list: [T], _ name: (T) -> String, _ make: (T) -> MediaItem) -> [MediaItem] {
                    var hits: [(Int, Int, T)] = []
                    for x in list { if let s = score(name(x)) { hits.append((s, name(x).count, x)); if hits.count > 2000 { break } } }
                    hits.sort { ($0.0, $0.1) < ($1.0, $1.1) }
                    var seen = Set<String>(), out: [MediaItem] = []
                    for h in hits {
                        let m = make(h.2)
                        if seen.insert(m.name.lowercased()).inserted { out.append(m) }
                        if out.count >= maxHits { break }
                    }
                    return out
                }
                var chans: [(Channel, String)] = []
                for (cc, gs) in groups {
                    for g in gs { for c in live[g.id] ?? [] { chans.append((c, Countries.name(cc) + " · " + Clean.titleCase(Clean.category(g.name)))) } }
                }
                let c = best(chans, { $0.0.name }) { MediaItem(kind: .live, id: $0.0.id, name: $0.0.name, img: $0.0.icon, sub: $0.1) }
                let f = best(films, \.name) { MediaItem(kind: .film, id: $0.id, name: $0.name, img: $0.img, ext: $0.ext) }
                let s = best(series, \.name) { MediaItem(kind: .series, id: $0.id, name: $0.name, img: $0.img) }
                func merge(_ a: [MediaItem], _ kind: ItemKind) -> [MediaItem] {
                    let more = best(extra.filter { $0.kind == kind }, \.name) { $0 }
                    var seen = Set(a.map { $0.name.lowercased() }), out = a
                    for m in more where out.count < maxHits && seen.insert(m.name.lowercased()).inserted { out.append(m) }
                    return out
                }
                // other languages after the main results; the same title in two languages stays two tiles
                func others(_ k: String) -> [MediaItem] {
                    var hits: [(Int, Int, MoreEntry)] = []
                    for x in other where x.k == k { if let sc = score(x.n) { hits.append((sc, x.n.count, x)); if hits.count > 2000 { break } } }
                    hits.sort { ($0.0, $0.1) < ($1.0, $1.1) }
                    var seen = Set<String>(), out: [MediaItem] = []
                    for h in hits where seen.insert(h.2.n.lowercased() + "|" + h.2.l).inserted {
                        out.append(MediaItem(kind: k == "f" ? .film : .series, id: h.2.i, name: h.2.n, ext: h.2.x, lang: h.2.l.isEmpty ? "?" : h.2.l))
                        if out.count >= maxHits { break }
                    }
                    return out
                }
                // channels of the other countries: one tile per name and country, with the country code as badge
                var oc: [(Int, Int, Channel, String)] = []
                for (cat, code) in otherLive {
                    for ch in live[cat] ?? [] { if let sc = score(ch.name) { oc.append((sc, ch.name.count, ch, code)) } }
                }
                for x in other where x.k == "c" {
                    if let sc = score(x.n) { oc.append((sc, x.n.count, Channel(id: x.i, name: x.n, icon: "", categoryId: ""), x.l)) }
                }
                oc.sort { ($0.0, $0.1, $0.3) < ($1.0, $1.1, $1.3) }
                var seenC = Set<String>(), otherChans: [MediaItem] = []
                for h in oc where seenC.insert(h.2.name.lowercased() + "|" + h.3).inserted {
                    otherChans.append(MediaItem(kind: .live, id: h.2.id, name: h.2.name, img: h.2.icon, sub: Countries.name(h.3), lang: h.3))
                    if otherChans.count >= maxHits { break }
                }
                return [merge(c, .live), merge(f, .film), merge(s, .series), otherChans, others("f"), others("s")]
            }.value
        }
    }
}
