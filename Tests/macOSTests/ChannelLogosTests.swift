import XCTest
@testable import NexusTVMac

/// Name cleaning, twins, iptv-org matching and the wordmark colour, on small fixtures. No download.
final class ChannelLogosTests: XCTestCase {
    func testCleaningStripsQualityPrefixAndBrackets() {
        XCTAssertEqual(LogoName.parse("PLAY 4 FHD").name, "PLAY 4")
        XCTAssertEqual(LogoName.parse("PLAY 4 FHD").quality, "FHD")
        XCTAssertEqual(LogoName.parse("US: CNN HD").name, "CNN")
        XCTAssertEqual(LogoName.parse("US: CNN HD").country, "US")
        XCTAssertEqual(LogoName.parse("ENF| TF1 HEVC").country, "FR")
        XCTAssertEqual(LogoName.parse("BE| VRT 1 (BACKUP) [RAW]").name, "VRT 1")
        XCTAssertEqual(LogoName.parse("BRAVO LQ").quality, "LQ")
        XCTAssertEqual(LogoName.parse("SKY SPORTS UHD").quality, "4K")
        XCTAssertEqual(LogoName.parse("AFC Champions League 3").name, "AFC Champions League 3")
        XCTAssertNil(LogoName.parse("NICK JUNIOR").quality)
    }

    func testKeyFoldsAccentsCaseAndPunctuation() {
        XCTAssertEqual(LogoName.parse("Canal+ HD").key, LogoName.parse("CANAL+ FHD").key)
        XCTAssertEqual(LogoName.parse("Één").key, "een")
        XCTAssertNotEqual(LogoName.parse("PLAY 4").key, LogoName.parse("PLAY 5").key)
    }

    func testCountryFromTheListLabel() {
        XCTAssertEqual(LogoName.country(fromSub: "Belgium · Algemeen"), "BE")
        XCTAssertEqual(LogoName.country(fromSub: "UK · Sports"), "GB")
        XCTAssertNil(LogoName.country(fromSub: ""))
    }

    func testTwinTakesTheLogoOfTheSameCleanedName() {
        let idx = ["a": [Channel(id: "1", name: "BE| VTM FHD", icon: "http://x.test/vtm.png", categoryId: "a"),
                         Channel(id: "2", name: "BE| VTM LQ", icon: "", categoryId: "a"),
                         Channel(id: "3", name: "BE| VTM 2", icon: "http://x.test/vtm2.png", categoryId: "a"),
                         Channel(id: "4", name: "BE| EVENT 7", icon: "", categoryId: "a")]]
        let twins = ChannelLogos.buildTwins(from: idx)
        XCTAssertEqual(twins[LogoName.parse("BE| VTM LQ").key], "http://x.test/vtm.png")
        XCTAssertEqual(twins[LogoName.parse("VTM 2").key], "http://x.test/vtm2.png", "VTM 2 is not VTM")
        XCTAssertNil(twins[LogoName.parse("EVENT 7").key])
    }

    private func iptv() -> IptvOrgIndex {
        let ch = """
        [{"id":"VTM.be","name":"VTM","alt_names":["VTM Vlaanderen"],"country":"BE"},
         {"id":"Sport1.nl","name":"Sport 1","alt_names":[],"country":"NL"},
         {"id":"Sport1.be","name":"Sport 1","alt_names":[],"country":"BE"},
         {"id":"Eurosport.fr","name":"Eurosport","alt_names":[],"country":"FR"},
         {"id":"Eurosport.de","name":"Eurosport","alt_names":[],"country":"DE"},
         {"id":"Nolog.be","name":"No Logo","alt_names":[],"country":"BE"}]
        """.data(using: .utf8)!
        let lg = """
        [{"channel":"VTM.be","url":"https://l.test/vtm-small.png","width":100},
         {"channel":"VTM.be","url":"https://l.test/vtm-wide.png","width":800},
         {"channel":"Sport1.nl","url":"https://l.test/s1nl.png","width":300},
         {"channel":"Sport1.be","url":"https://l.test/s1be.png","width":300},
         {"channel":"Eurosport.fr","url":"https://l.test/esfr.png","width":300},
         {"channel":"Eurosport.de","url":"https://l.test/esde.png","width":300}]
        """.data(using: .utf8)!
        return IptvOrgIndex(channelsJSON: ch, logosJSON: lg)
    }

    func testIptvOrgTakesTheWidestLogoOfAnExactName() {
        let i = iptv()
        XCTAssertEqual(i.url(forKey: LogoName.parse("VTM").key, country: nil), "https://l.test/vtm-wide.png")
        XCTAssertEqual(i.url(forKey: LogoName.parse("vtm vlaanderen").key, country: "BE"), "https://l.test/vtm-wide.png", "alternative name")
    }

    func testIptvOrgPrefersTheSameCountryAndNeverGuesses() {
        let i = iptv()
        XCTAssertEqual(i.url(forKey: LogoName.parse("Sport 1").key, country: "BE"), "https://l.test/s1be.png")
        XCTAssertNil(i.url(forKey: LogoName.parse("Sport 1").key, country: nil), "two countries, no hint: none")
        XCTAssertNil(i.url(forKey: LogoName.parse("Eurosport").key, country: "BE"), "other countries only: none")
        XCTAssertNil(i.url(forKey: LogoName.parse("Sport").key, country: "BE"), "no partial match")
        XCTAssertNil(i.url(forKey: LogoName.parse("No Logo").key, country: "BE"), "a channel without a logo")
    }

    func testWordmarkHueIsStablePerName() {
        XCTAssertEqual(WordmarkTile.hue("PLAY 4"), WordmarkTile.hue("PLAY 4"))
        XCTAssertNotEqual(WordmarkTile.hue("PLAY 4"), WordmarkTile.hue("NICK JUNIOR"))
        XCTAssertTrue((0..<360).contains(WordmarkTile.hue("AFC Champions League 3")))
    }
}
