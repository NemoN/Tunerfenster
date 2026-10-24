import XCTest
@testable import Tunerfenster

final class RecordingTitleTests: XCTestCase {
    func testBareTatortUsesTheEpisodeSubtitleIncludingLocalizedMetadata() throws {
        let data = Data(#"{"uuid":"charlie","title":{"ger":"Tatort","eng":"Tatort"},"subtitle":{"ger":"Charlie","eng":"Charlie"},"filesize":100,"sched_status":"completed"}"#.utf8)
        let item = try JSONDecoder().decode(SavedRecording.self, from: data)
        XCTAssertEqual(item.name, "Tatort: Charlie")
        XCTAssertTrue(item.matches("Charlie"))
        XCTAssertEqual(item.id, "charlie")
        XCTAssertEqual(item.subtitleText, "Charlie")
    }

    func testAlreadyCompleteTitlesStayUnchanged() {
        for title in ["Tatort: Der Stelzenmann", "Tatort – Charlie", "Tatort: Man stirbt nur zweimal", "Morse - Dead on Time", "Show: The Finale"] {
            XCTAssertEqual(RecordingTitle.display(title, subtitle: "Krimi (D 2025)", detail: "Episode: Charlie"), title)
        }
    }

    func testOtherSeriesAndMagazinesUseTheirEpisodeSubtitles() {
        XCTAssertEqual(RecordingTitle.display("Inspector Morse", subtitle: "Dead on Time", detail: nil), "Inspector Morse: Dead on Time")
        XCTAssertEqual(RecordingTitle.display("K1 Magazin", subtitle: "Indoor-Wasserparks im Test", detail: "Genre: Magazin"), "K1 Magazin: Indoor-Wasserparks im Test")
        XCTAssertEqual(RecordingTitle.display("Abenteuer Leben täglich", subtitle: "Do it yourself – Holzterrasse", detail: "Genre: Wissensmagazin"), "Abenteuer Leben täglich: Do it yourself – Holzterrasse")
    }

    func testSeriesMetadataAllowsSeriesNamesContainingColonsAndDashes() {
        let title = "Inside Star Trek - Hinter den Kulissen des Enterprise-Universums"
        let detail = "Genre: Dokumentation\nSerie: \(title)\nEpisode: Die Zeichentrickserie"
        XCTAssertEqual(RecordingTitle.display(title, subtitle: "Die Zeichentrickserie", detail: detail), title + ": Die Zeichentrickserie")
        XCTAssertEqual(RecordingTitle.display("Star Trek: Voyager", subtitle: nil, detail: "Series title: Star Trek: Voyager\nEpisode title: The Chute"), "Star Trek: Voyager: The Chute")
    }

    func testExistingEpisodeTitlesAndConflictingSeriesMetadataArePreserved() {
        for title in ["Morse: Dead on Time", "Dead on Time", "A different programme"] {
            XCTAssertEqual(RecordingTitle.display(title, subtitle: "Another episode", detail: "Series: Inspector Morse\nEpisode: Another episode"), title)
        }
        XCTAssertEqual(RecordingTitle.display("Show The Final Hour", subtitle: "the final hour", detail: nil), "Show The Final Hour")
        XCTAssertEqual(RecordingTitle.display("Serie: Die Ärztin", subtitle: "DIE ARZTIN", detail: nil), "Serie: Die Ärztin")
    }

    func testDuplicatesIgnoreCasePunctuationAndRepeatedSeriesPrefixes() {
        XCTAssertEqual(RecordingTitle.display("Dr. House", subtitle: "DR HOUSE — DR. HOUSE: Die Premiere", detail: nil), "Dr. House: Die Premiere")
        XCTAssertEqual(RecordingTitle.display("Die Ärztin", subtitle: "DIE ARZTIN – Die Operation", detail: nil), "Die Ärztin: Die Operation")
        XCTAssertEqual(RecordingTitle.display("Show (2024)", subtitle: "SHOW (2024): Pilot", detail: nil), "Show (2024): Pilot")
        XCTAssertEqual(RecordingTitle.display("Show", subtitle: "Show - Show", detail: nil), "Show")
        XCTAssertEqual(RecordingTitle.display("Arthur", subtitle: "Art", detail: nil), "Arthur: Art", "A partial word is not an episode already present in the title")
    }

    func testGenreOriginAndYearMetadataAreNeverAppendedInEitherLanguage() {
        let subtitles = ["Krimi (D 2025)", "Comedyserie (DE 2024)", "Dokumentation (D2023)", "Doku-Reihe, Deutschland 2024",
                         "Science-Fiction-Serie / USA 2020", "Drama series (UK, 2024)", "British crime drama 2023",
                         "TV Movie (US 2018)", "Documentary", "Crime / Drama", "Genre: Komödie", "USA 2024", "Fernsehfilm"]
        for subtitle in subtitles {
            XCTAssertEqual(RecordingTitle.display("My Programme", subtitle: subtitle, detail: nil), "My Programme", subtitle)
        }
        XCTAssertEqual(RecordingTitle.display("My Programme", subtitle: "Alltagsbeobachtung (D 2024)", detail: "Genre: Alltagsbeobachtung"), "My Programme")
    }

    func testInvalidEpisodeFieldFallsBackToARealSubtitleButProseDoesNot() {
        XCTAssertEqual(RecordingTitle.display("My Programme", subtitle: "The Departure", detail: "Episode: Documentary\nGenre: Documentary"), "My Programme: The Departure")
        XCTAssertEqual(RecordingTitle.display("My Programme", subtitle: nil, detail: "The Departure\nA summary about the journey."), "My Programme")
        XCTAssertEqual(RecordingTitle.display("My Programme", subtitle: "First line\nSecond line", detail: nil), "My Programme")
    }

    func testMissingTitleAndMissingMetadataKeepTheirFallbacks() {
        let item = SavedRecording(uuid: "missing", disp_subtitle: "The Departure")
        XCTAssertEqual(item.name, L10n.text("untitledRecording"))
        XCTAssertEqual(RecordingTitle.display("Programme", subtitle: nil, detail: nil), "Programme")
        XCTAssertEqual(RecordingTitle.display("Programme", subtitle: "Programme", detail: nil), "Programme")
    }

    func testExplicitEpisodeFieldWorksWithoutSubtitleAndWinsOverGenreText() {
        let detail = "Genre: Krimi\n\nBeschreibung der Sendung.\nSerie: Tatort\nEpisode: Charlie\nFolge: 1294"
        XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: nil, detail: detail), "Tatort: Charlie")
        XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: "Krimi (D 2025)", detail: detail), "Tatort: Charlie")
        XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: nil, detail: "Episode:  \nFOLGENTITEL:  Unter Feuer  "), "Tatort: Unter Feuer")
    }

    func testDescriptionsAndEmptyOrGenreOnlySubtitlesDoNotBecomeEpisodeTitles() {
        for subtitle in [nil, "", "   ", "Tatort", "Krimi (D 2025)", "Fernsehfilm", "Zeile eins\nZeile zwei"] {
            XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: subtitle, detail: "Charlie\nEin Film über einen Tatort."), "Tatort")
        }
    }

    func testCaseWhitespaceAndRepeatedSeriesPrefixDoNotDuplicateTheTitle() {
        XCTAssertEqual(RecordingTitle.display(" Tatort ", subtitle: " Charlie ", detail: nil), "Tatort: Charlie")
        for subtitle in ["Tatort: Charlie", "tatort – Charlie", "Tatort - Charlie", "Tatort—Charlie"] {
            XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: subtitle, detail: nil), "Tatort: Charlie")
        }
        XCTAssertEqual(RecordingTitle.display("Tatort", subtitle: "Tatort: ", detail: nil), "Tatort")
        XCTAssertEqual(RecordingTitle.display("TATORT", subtitle: "Charlie", detail: nil), "TATORT: Charlie")
    }

    func testEpisodeNamesDriveNaturalNameSortingAndSearch() {
        let items = [SavedRecording(uuid: "ten", disp_title: "Tatort", disp_subtitle: "Folge 10"),
                     SavedRecording(uuid: "two", disp_title: "Tatort", disp_subtitle: "Folge 2")]
        XCTAssertEqual(RecordingSort.nameAscending.sorted(items).map(\.id), ["two", "ten"])
        XCTAssertTrue(items[0].matches("Tatort: Folge 10"))
        XCTAssertEqual(items[0].disp_title, "Tatort")
    }

    func testFolderPrefixIsOmittedOnlyFromTitlesShownInsideThatFolder() {
        for title in ["Tatort: Charlie", "Tatort – Charlie", "Tatort - Charlie", "Tatort—Charlie"] {
            XCTAssertEqual(RecordingTitle.withoutFolderPrefix(title, folders: ["Tatort"]), "Charlie")
            XCTAssertEqual(RecordingTitle.withoutFolderPrefix(title, folders: []), title)
        }
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix("DIE ARZTIN: Die Operation", folders: ["Die Ärztin"]), "Die Operation")
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix("[Kids]: The Pilot", folders: ["[Kids]"]), "The Pilot")
        let name = "Inside Star Trek - Hinter den Kulissen des Enterprise-Universums"
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix(name + ": Die Zeichentrickserie", folders: [name]), "Die Zeichentrickserie")
    }

    func testVisibleAncestorPrefixesAreRemovedWithoutLosingEpisodeText() {
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix("Series: Season 2: The Return", folders: ["Series", "Season 2"]), "The Return")
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix("Star Trek: Voyager: The Chute", folders: ["Star Trek", "Star Trek: Voyager"]), "The Chute")
        for title in ["Tatort", "Tatort: ", "Tatortreiniger: Die Premiere", "Der Tatort: Charlie", "Tatort ohne Folge"] {
            XCTAssertEqual(RecordingTitle.withoutFolderPrefix(title, folders: ["Tatort"]), title)
        }
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix("Tatort: Charlie", folders: ["Crime"]), "Tatort: Charlie")
    }

    func testShortFolderTitleLeavesTheFullRecordingNameAndSearchUnchanged() {
        let item = SavedRecording(uuid: "charlie", disp_title: "Tatort", disp_subtitle: "Charlie")
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix(item.name, folders: ["Tatort"]), "Charlie")
        XCTAssertEqual(item.name, "Tatort: Charlie")
        XCTAssertTrue(item.matches("Tatort: Charlie"))
        XCTAssertEqual(RecordingTitle.withoutFolderPrefix(item.name, folders: []), "Tatort: Charlie")
    }
}
