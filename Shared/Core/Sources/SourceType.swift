import Foundation

/// The three ways to reach a library. One protocol (LibrarySource) sits behind all of them.
enum SourceType: String, Codable, CaseIterable, Sendable {
    case xtream = "x", m3u = "m", portal = "p"

    var title: String {
        switch self { case .xtream: "Xtream login"; case .m3u: "M3U playlist"; case .portal: "Portal" }
    }
    /// SF Symbol for the Sources list.
    var icon: String {
        switch self { case .xtream: "server.rack"; case .m3u: "link"; case .portal: "key" }
    }
    var sub: String {
        switch self {
        case .xtream: "Use the server and login your service gave you."
        case .m3u: "Paste the playlist link your service gave you."
        case .portal: "Use the portal link and the MAC address your service registered."
        }
    }
    /// Rows of the form: SF Symbol, label, placeholder.
    var rows: [(icon: String, label: String, hint: String)] {
        switch self {
        case .xtream: [("server.rack", "Server", "http://server:port"), ("person", "Username", "Username"), ("key", "Password", "Password")]
        case .m3u: [("server.rack", "Playlist", "https://…/playlist.m3u"), ("books.vertical", "TV guide", "Optional EPG link (XMLTV)"), ("person", "Name", "My playlist")]
        case .portal: [("server.rack", "Portal", "http://portal:port/c/"), ("key", "MAC", "00:1A:79:00:00:00"), ("person", "Name", "My portal")]
        }
    }
    /// Indexes of the rows that must be filled.
    var required: [Int] {
        switch self { case .xtream: [0, 1, 2]; case .m3u: [0]; case .portal: [0, 1] }
    }
    var needMessage: String {
        switch self {
        case .xtream: "Server, username and password are all needed."
        case .m3u: "The playlist link is needed."
        case .portal: "The portal link and the MAC address are needed."
        }
    }
}

enum SourceError: Error, Equatable {
    case unreachable, refused, notAPlaylist, cancelled
}

/// The result of checking a source before it is saved. `marks` says which of the three form rows turn red or green.
enum CheckStage: Equatable, Sendable { case ok, server, auth, invalid, cancel }

enum RowMark: Equatable, Sendable { case none, ok, bad }
