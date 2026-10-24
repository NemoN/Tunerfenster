import XCTest
@testable import Tunerfenster

final class RecordingListStateTests: XCTestCase {
    func testFolderExpansionSurvivesRecreationAndSavesCollapsedFolders() throws {
        let name = "Tunerfenster.RecordingListStateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = RecordingListPreferences(defaults: defaults)
        XCTAssertTrue(first.expandedFolders.isEmpty)
        let folders: Set<String> = ["14:/recordings4:News", "14:/recordings6:Krimis8:Staffel 2"]
        first.expandedFolders = folders
        let restored = RecordingListPreferences(defaults: defaults)
        XCTAssertEqual(restored.expandedFolders, folders)
        restored.expandedFolders = ["14:/recordings4:News"]
        XCTAssertEqual(RecordingListPreferences(defaults: defaults).expandedFolders, ["14:/recordings4:News"])
        restored.expandedFolders = []
        XCTAssertTrue(RecordingListPreferences(defaults: defaults).expandedFolders.isEmpty)
    }

    func testInvalidPreferencesFallBackWithoutLosingOtherSettings() throws {
        let name = "Tunerfenster.RecordingListStateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("invalid", forKey: RecordingListPreferences.foldersKey)
        defaults.set("dateOldest", forKey: RecordingSort.preferenceKey)
        let preferences = RecordingListPreferences(defaults: defaults)
        XCTAssertTrue(preferences.expandedFolders.isEmpty)
        preferences.expandedFolders = ["folder"]
        XCTAssertEqual(defaults.string(forKey: RecordingSort.preferenceKey), "dateOldest")
    }

    func testListDatePadsDayMonthAndTimeInBothLanguages() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 11, day: 3, hour: 8, minute: 5)))
        var recording = SavedRecording(uuid: "date", start: date.timeIntervalSince1970)
        XCTAssertEqual(recording.listDateLabel(locale: Locale(identifier: "de_DE"), timeZone: zone), "03.11.2024, 08:05")
        XCTAssertEqual(recording.listDateLabel(locale: Locale(identifier: "en_GB"), timeZone: zone), "03/11/2024, 08:05")
        let march = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 2, hour: 20, minute: 20)))
        recording.start = march.timeIntervalSince1970
        XCTAssertEqual(recording.listDateLabel(locale: Locale(identifier: "de_DE"), timeZone: zone), "02.03.2025, 20:20")
    }

    func testDurationLabelsUseHoursMinutesAndSecondsWithoutWrappingAtADay() {
        for (duration, label) in [(5379.0, "1:29:39"), (301, "0:05:01"), (90061, "25:01:01"), (3599.9, "0:59:59")] {
            let recording = SavedRecording(uuid: "duration", duration: duration)
            XCTAssertEqual(recording.compactDurationLabel, label)
        }
        let fallback = SavedRecording(uuid: "fallback", start: 100, stop: 3700)
        XCTAssertEqual(fallback.compactDurationLabel, "1:00:00")
        XCTAssertEqual(SavedRecording(uuid: "explicit", start: 100, stop: 3700, duration: 60).compactDurationLabel, "0:01:00")
    }

    func testUnknownAndInvalidDurationsDoNotInventARecordingLength() {
        for duration in [0, -10, Double.nan, .infinity, .greatestFiniteMagnitude] {
            XCTAssertNil(SavedRecording(uuid: "invalid", duration: duration).compactDurationLabel)
        }
        for recording in [SavedRecording(uuid: "missing"), SavedRecording(uuid: "start-only", start: 100),
                          SavedRecording(uuid: "stop-only", stop: 1_700_000_000),
                          SavedRecording(uuid: "reversed", start: 100, stop: 50)] {
            XCTAssertNil(recording.compactDurationLabel)
            XCTAssertEqual(recording.recordedDuration, 0)
        }
    }

    func testDurationIsTheLastMetadataColumnHiddenForTheWholeList() {
        let recording = SavedRecording(uuid: "layout", channelname: "Das Erste HD", start: 1_740_947_400, duration: 5379)
        let columns = RecordingMetadataColumns(items: [recording])
        XCTAssertEqual(columns.visibility(inListWidth: 1000), .all)
        XCTAssertEqual(columns.visibility(inListWidth: 400), .durationOnly)
        XCTAssertEqual(columns.visibility(inListWidth: 280), .titleOnly)
        var previous = RecordingMetadataColumns.Visibility.titleOnly
        for width in stride(from: 280, through: 1000, by: 1) {
            let current = columns.visibility(inListWidth: CGFloat(width))
            if previous == .all { XCTAssertEqual(current, .all) }
            if previous == .durationOnly { XCTAssertNotEqual(current, .titleOnly) }
            previous = current
        }
    }
}
