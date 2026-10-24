import XCTest
@testable import Tunerfenster

final class RecordingSortTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private func item(_ id: String, _ name: String, _ date: Double?, duration: Double? = nil) -> SavedRecording {
        SavedRecording(uuid: id, disp_title: name, start: date, duration: duration, filesize: 100, sched_status: "completed")
    }

    func testNaturalNameSortInBothDirectionsUsesDateForRepeatedTitles() {
        let items = [item("ten", "Episode 10", 1), item("two-old", "Episode 2", 10),
                     item("two-new", "episode 2", 20), item("alpha", "Alpha", 30)]
        XCTAssertEqual(RecordingSort.nameAscending.sorted(items, locale: locale).map(\.id), ["alpha", "two-new", "two-old", "ten"])
        XCTAssertEqual(RecordingSort.nameDescending.sorted(items, locale: locale).map(\.id), ["ten", "two-new", "two-old", "alpha"])
    }

    func testDateSortKeepsMissingAndNonFiniteDatesLastInBothDirections() {
        let items = [item("nil", "C", nil), item("new", "New", 100), item("nan", "A", .nan),
                     item("old", "Old", 1), item("inf", "B", .infinity)]
        XCTAssertEqual(RecordingSort.dateNewest.sorted(items, locale: locale).map(\.id), ["new", "old", "nan", "inf", "nil"])
        XCTAssertEqual(RecordingSort.dateOldest.sorted(items, locale: locale).map(\.id), ["old", "new", "nan", "inf", "nil"])
        XCTAssertNil(items[2].compactDateLabel)
        XCTAssertNil(items[4].dateLabel)
    }

    func testEqualDatesUseNaturalNamesAndEqualNamesHaveStableIdentifiers() {
        let items = [item("z", "Episode 2", 100), item("ten", "Episode 10", 100), item("a", "Episode 2", 100)]
        for order in RecordingSort.allCases {
            let sorted = order.sorted(items, locale: locale).map(\.id)
            XCTAssertEqual(sorted, order == .nameDescending ? ["ten", "a", "z"] : ["a", "z", "ten"])
        }
    }

    func testFolderDatesIncludeNestedRecordingsAndFolderIdentityStaysStable() {
        let a = item("a", "Episode 10", 40), b = item("b", "Episode 2", 20), c = item("c", "Nested", 100)
        let tree = RecordingFolderTree(items: [a, b, c].map { item in
            var result = item
            result.filename = "/recordings/\(item.id == "c" ? "Series/Season 2" : "Films")/\(item.id).ts"
            return result
        }, storageRoots: [.init(uuid: "root", storage: "/recordings")])
        let newest = tree.sorted(using: .dateNewest), oldest = tree.sorted(using: .dateOldest)
        XCTAssertEqual(newest.folders.map(\.name), ["Series", "Films"])
        XCTAssertEqual(oldest.folders.map(\.name), ["Films", "Series"])
        XCTAssertEqual(newest.folders.last?.recordings.map(\.id), ["a", "b"])
        XCTAssertEqual(oldest.folders.first?.recordings.map(\.id), ["b", "a"])
        let names = tree.sorted(using: .nameAscending)
        XCTAssertEqual(names.folders.map(\.name), ["Films", "Series"])
        XCTAssertEqual(names.folders.first?.recordings.map(\.id), ["b", "a"])
        XCTAssertEqual(newest.paths, tree.paths)
        XCTAssertEqual(newest.ancestors, tree.ancestors)
        XCTAssertEqual(newest.folders.map(\.count), [1, 2])
    }

    func testSortingAlsoAppliesToUnfiledAndNestedFolders() {
        let folders = [RecordingFolder(id: "series", name: "Series", folders: [
            RecordingFolder(id: "ten", name: "Season 10", recordings: [item("ten", "Ten", 100)]),
            RecordingFolder(id: "two", name: "Season 2", recordings: [item("two", "Two", 200)])
        ])]
        XCTAssertEqual(RecordingSort.nameAscending.sorted(folders: folders).first?.folders.map(\.id), ["two", "ten"])
        XCTAssertEqual(RecordingSort.nameDescending.sorted(folders: folders).first?.folders.map(\.id), ["ten", "two"])
        XCTAssertEqual(RecordingSort.dateNewest.sorted(folders: folders).first?.folders.map(\.id), ["two", "ten"])
        let tree = RecordingFolderTree(items: [item("b", "B", 1), item("a", "A", 2)], storageRoots: [])
        XCTAssertEqual(tree.sorted(using: .nameAscending).unfiled.map(\.id), ["a", "b"])
        XCTAssertEqual(tree.sorted(using: .dateOldest).unfiled.map(\.id), ["b", "a"])
    }

    func testSortControlsToggleAndSwitchFieldsWithSensibleDefaults() {
        XCTAssertEqual(RecordingSort.dateNewest.selecting(.date), .dateOldest)
        XCTAssertEqual(RecordingSort.dateOldest.selecting(.date), .dateNewest)
        XCTAssertEqual(RecordingSort.dateOldest.selecting(.name), .nameAscending)
        XCTAssertEqual(RecordingSort.nameAscending.selecting(.name), .nameDescending)
        XCTAssertEqual(RecordingSort.nameDescending.selecting(.date), .dateNewest)
        XCTAssertEqual(RecordingSort.dateOldest.selecting(.duration), .durationLongest)
        XCTAssertEqual(RecordingSort.durationLongest.selecting(.duration), .durationShortest)
        XCTAssertEqual(RecordingSort.durationShortest.selecting(.duration), .durationLongest)
        XCTAssertTrue(RecordingSort.durationShortest.ascending)
        XCTAssertFalse(RecordingSort.durationLongest.ascending)
        for order in RecordingSort.allCases {
            XCTAssertEqual(RecordingSort(rawValue: order.rawValue), order)
            XCTAssertNotEqual(L10n.text(order.labelKey), order.labelKey)
        }
    }

    func testFoldersAndRecordingsShareNaturalNameOrderInBothDirections() {
        let folders = [RecordingFolder(id: "ten", name: "Episode 10", recordings: [item("inside-ten", "Film", 30)]),
                       RecordingFolder(id: "alpha", name: "Alpha", recordings: [item("inside-alpha", "Film", 40)])]
        let recordings = [item("omega", "Omega", 20), item("two", "episode 2", 10)]
        XCTAssertEqual(RecordingSort.nameAscending.sorted(folders: folders, recordings: recordings, locale: locale).map(\.name),
                       ["Alpha", "episode 2", "Episode 10", "Omega"])
        XCTAssertEqual(RecordingSort.nameDescending.sorted(folders: folders, recordings: recordings, locale: locale).map(\.name),
                       ["Omega", "Episode 10", "episode 2", "Alpha"])
    }

    func testMixedDateOrderUsesNewestNestedRecordingAndKeepsUnknownDatesLast() {
        let folders = [RecordingFolder(id: "nested", name: "Nested", folders: [
            RecordingFolder(id: "season", name: "Season", recordings: [item("latest", "Episode", 300), item("invalid", "Invalid", .infinity)])
        ], recordings: [item("older", "Older", 5)]),
                       RecordingFolder(id: "old", name: "Old", recordings: [item("inside-old", "Episode", 10)]),
                       RecordingFolder(id: "unknown", name: "Unknown folder", recordings: [item("inside-nan", "Episode", .nan)])]
        let recordings = [item("middle", "Middle", 150), item("newest", "Newest", 400), item("unknown", "Unknown recording", nil)]
        XCTAssertEqual(RecordingSort.dateNewest.sorted(folders: folders, recordings: recordings, locale: locale).map(\.name),
                       ["Newest", "Nested", "Middle", "Old", "Unknown folder", "Unknown recording"])
        XCTAssertEqual(RecordingSort.dateOldest.sorted(folders: folders, recordings: recordings, locale: locale).map(\.name),
                       ["Old", "Middle", "Nested", "Newest", "Unknown folder", "Unknown recording"])
    }

    func testMixedSortingIncludesPromotedSingleRecordingsInsideAnExpandedFolder() throws {
        let items = [item("alpha", "Alpha", 50), item("zulu", "Zulu", 100),
                     item("one", "Episode 1", 60), item("two", "Episode 2", 70)].map { item in
            var result = item
            let directory = item.id == "alpha" ? "Single" : item.id == "zulu" ? "" : "Middle"
            result.filename = "/recordings/Series/\(directory)/\(item.id).ts"
            return result
        }
        let tree = RecordingFolderTree(items: items, storageRoots: [.init(uuid: "root", storage: "/recordings")])
            .flatteningSingleRecordingFolders()
        let series = try XCTUnwrap(tree.folders.first)
        XCTAssertEqual(RecordingSort.nameAscending.sorted(folders: series.folders, recordings: series.recordings, locale: locale).map(\.name),
                       ["Alpha", "Middle", "Zulu"])
        XCTAssertEqual(RecordingSort.dateNewest.sorted(folders: series.folders, recordings: series.recordings, locale: locale).map(\.name),
                       ["Zulu", "Middle", "Alpha"])
        XCTAssertEqual(series.count, items.count)
    }

    func testMixedEntriesHaveStableDistinctIdentitiesWhenNamesDatesAndRawIDsMatch() {
        let folder = RecordingFolder(id: "shared", name: "Same", recordings: [item("inside", "Episode", 100)])
        let recording = item("shared", "Same", 100)
        for order in RecordingSort.allCases {
            let entries = order.sorted(folders: [folder], recordings: [recording], locale: locale)
            XCTAssertEqual(entries.map(\.id), ["folder/shared", "recording/shared"])
            XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        }
    }

    func testNamesInsideFoldersSortByTheTitleActuallyShown() {
        let folders = [RecordingFolder(id: "beta", name: "Beta", recordings: [item("inside", "Film", 200)])]
        let recordings = [item("alpha", "Series: Alpha", 100), item("zulu", "Series: Zulu", 400), item("charlie", "Charlie", 300)]
        XCTAssertEqual(RecordingSort.nameAscending.sorted(folders: folders, recordings: recordings, within: ["Series"], locale: locale).map(\.id),
                       ["recording/alpha", "folder/beta", "recording/charlie", "recording/zulu"])
        XCTAssertEqual(RecordingSort.nameDescending.sorted(folders: folders, recordings: recordings, within: ["Series"], locale: locale).map(\.id),
                       ["recording/zulu", "recording/charlie", "folder/beta", "recording/alpha"])
        XCTAssertEqual(RecordingSort.nameAscending.sorted(folders: folders, recordings: recordings, locale: locale).map(\.id),
                       ["folder/beta", "recording/charlie", "recording/alpha", "recording/zulu"])
        XCTAssertEqual(RecordingSort.dateNewest.sorted(folders: folders, recordings: recordings, within: ["Series"], locale: locale).map(\.id),
                       ["recording/zulu", "recording/charlie", "folder/beta", "recording/alpha"])
    }

    func testDurationSortUsesSecondsAndKeepsUnknownValuesLastInEitherDirection() {
        var fallback = item("fallback", "Fallback", 100)
        fallback.stop = 700
        let items = [item("long", "Long", 20, duration: 7200), item("short", "Short", 30, duration: 300),
                     item("middle", "Middle", 10, duration: 1200), fallback,
                     item("nan", "Invalid", 40, duration: .nan), item("missing", "Missing", 50),
                     item("zero", "Zero", 60, duration: 0)]
        XCTAssertEqual(RecordingSort.durationShortest.sorted(items, locale: locale).map(\.id),
                       ["short", "fallback", "middle", "long", "nan", "missing", "zero"])
        XCTAssertEqual(RecordingSort.durationLongest.sorted(items, locale: locale).map(\.id),
                       ["long", "middle", "fallback", "short", "nan", "missing", "zero"])
    }

    func testEqualDurationsUseNaturalNamesThenNewestDatesInBothDirections() {
        let items = [item("ten", "Episode 10", 100, duration: 600), item("old", "Episode 2", 10, duration: 600),
                     item("new", "episode 2", 20, duration: 600)]
        for order in [RecordingSort.durationLongest, .durationShortest] {
            XCTAssertEqual(order.sorted(items, locale: locale).map(\.id), ["new", "old", "ten"])
        }
    }

    func testMixedDurationSortUsesTheLongestRecordingAnywhereInAFolder() {
        let nested = RecordingFolder(id: "season", name: "Season", recordings: [
            item("short-episode", "Episode 1", 1, duration: 440), item("long-episode", "Episode 2", 2, duration: 450)
        ])
        let folders = [RecordingFolder(id: "series", name: "Series", folders: [nested], recordings: [item("inside", "Film", 3, duration: 100)]),
                       RecordingFolder(id: "films", name: "Films", recordings: [
                        item("film1", "Film 1", 4, duration: 250), item("film2", "Film 2", 5, duration: 250)
                       ]), RecordingFolder(id: "unknown", name: "Unknown", recordings: [item("unknown", "Unknown", 6)])]
        let recordings = [item("direct", "Direct", 7, duration: 300)]
        XCTAssertEqual(RecordingSort.durationShortest.sorted(folders: folders, recordings: recordings, locale: locale).map(\.id),
                       ["folder/films", "recording/direct", "folder/series", "folder/unknown"])
        XCTAssertEqual(RecordingSort.durationLongest.sorted(folders: folders, recordings: recordings, locale: locale).map(\.id),
                       ["folder/series", "recording/direct", "folder/films", "folder/unknown"])
        let sorted = RecordingSort.durationLongest.sorted(folders: folders, locale: locale)
        XCTAssertEqual(sorted.map(\.id), ["series", "films", "unknown"])
        XCTAssertEqual(sorted.first?.folders.first?.recordings.map(\.id), ["long-episode", "short-episode"])
        XCTAssertEqual(sorted.first?.id, folders.first?.id)
    }
}
