import Foundation

/// Test hook for the simulator: `-NXLocalFile /path/to/video.mkv` plays that file instead of a provider stream (the
/// provider allows one connection, which a test must never take), and `-NXDemoSeries YES` gives the player a made-up
/// series with two seasons, so the episode strip and the end card can be driven without any account.
enum PlayerDemo {
    static var file: URL? {
        UserDefaults.standard.string(forKey: "NXLocalFile").map { URL(fileURLWithPath: $0) }
    }
    static var on: Bool { UserDefaults.standard.bool(forKey: "NXDemoSeries") }

    static func series() -> Details {
        let titles1 = ["The Funeral", "The Will", "Black Velvet", "The Dublin Trade", "Fenians", "The Brewery", "The Harp", "Stout"]
        let mins1 = [58, 55, 53, 57, 54, 56, 52, 60]
        let titles2 = ["Returns", "The Heir", "Vats"]
        var d = Details()
        d.name = "House Of Guinness"
        d.seasons = ["1", "2"]
        d.episodes = [
            "1": titles1.enumerated().map { Episode(id: "demo\($0.offset + 1)", num: $0.offset + 1, title: $0.element, ext: "mkv", still: "", durationSecs: mins1[$0.offset] * 60) },
            "2": titles2.enumerated().map { Episode(id: "demo2\($0.offset + 1)", num: $0.offset + 1, title: $0.element, ext: "mkv", still: "", durationSecs: 3300) },
        ]
        return d
    }
}
