import XCTest
@testable import Tunerfenster

final class RecordingListSnapshotTests: XCTestCase {
    private let roots = [RecordingStorage(uuid: "root", storage: "/recordings")]
    private func item(_ id: String, _ title: String, _ path: String, date: Double = 100, duration: Double = 3600) -> SavedRecording {
        SavedRecording(uuid: id, disp_title: title, channelname: "Channel", start: date, duration: duration,
                       filesize: 100, sched_status: "completed", filename: "/recordings/\(path)/\(id).ts")
    }

    func testPreparedRowsPreserveFullTitlesForSearchAndShortenOnlyVisibleFolderPrefixes() throws {
        let items = [item("one", "Tatort: Charlie", "Tatort"), item("two", "Tatort: Donuts", "Tatort"),
                     item("single", "News: Today", "News")]
        let snapshot = RecordingListSnapshot(items: items, storageRoots: roots, sort: .nameAscending, term: "")
        let row = try XCTUnwrap(snapshot.rows["one"])
        XCTAssertEqual(row.fullName, "Tatort: Charlie")
        XCTAssertEqual(row.folderTitle, "Charlie")
        XCTAssertTrue(row.description.contains("Tatort: Charlie"))
        XCTAssertTrue(row.playLabel.contains("Tatort: Charlie"))
        XCTAssertEqual(snapshot.rows["single"]?.folderTitle, "News: Today")
        XCTAssertEqual(snapshot.rootEntries.map(\.name), ["News: Today", "Tatort"])
        let folder = try XCTUnwrap(snapshot.tree.folders.first)
        XCTAssertEqual(snapshot.folderEntries[folder.id]?.map(\.id), ["recording/one", "recording/two"])
        for term in ["Charlie", "Channel", "Tatort"] {
            let searched = RecordingListSnapshot(items: items, storageRoots: roots, sort: .nameAscending, term: term)
            XCTAssertTrue(searched.filtered.contains { $0.id == "one" })
        }
        XCTAssertTrue(RecordingListSnapshot(items: items, storageRoots: roots, sort: .nameAscending, term: "absent").filtered.isEmpty)
    }

    func testSnapshotOrdersAllLevelsLikeTheCatalogueForEverySortDirection() {
        let items = [item("one", "Crime: Episode 10", "Crime", date: 30, duration: 200),
                     item("two", "Crime: Episode 2", "Crime", date: 10, duration: 100),
                     item("three", "Nested: Z", "Crime/Nested", date: 50, duration: 300),
                     item("four", "Nested: A", "Crime/Nested", date: 70, duration: 500),
                     item("single", "Alone", "Single", date: 80, duration: 400)]
        for sort in RecordingSort.allCases {
            let snapshot = RecordingListSnapshot(items: items, storageRoots: roots, sort: sort, term: "")
            XCTAssertEqual(snapshot.rootEntries.map(\.id), sort.sorted(folders: snapshot.tree.folders, recordings: snapshot.tree.unfiled).map(\.id))
            func check(_ folders: [RecordingFolder], ancestors: [String]) {
                for folder in folders {
                    let names = ancestors + [folder.name]
                    XCTAssertEqual(snapshot.folderEntries[folder.id]?.map(\.id),
                                   sort.sorted(folders: folder.folders, recordings: folder.recordings, within: names).map(\.id))
                    check(folder.folders, ancestors: names)
                }
            }
            check(snapshot.tree.folders, ancestors: [])
        }
    }

    func testCacheReusesLayoutDataButRebuildsForSortSearchLanguageAndInvalidation() {
        let defaults = UserDefaults.standard, old = defaults.object(forKey: "interfaceLanguage")
        defer { if let old { defaults.set(old, forKey: "interfaceLanguage") } else { defaults.removeObject(forKey: "interfaceLanguage") } }
        defaults.set("de", forKey: "interfaceLanguage")
        let cache = RecordingListCache(), items = [item("one", "Title", "Folder")]
        func snapshot(_ sort: RecordingSort = .dateNewest, _ search: String = "") -> RecordingListSnapshot {
            cache.snapshot(items: items, storageRoots: roots, sort: sort, search: search)
        }
        let first = snapshot()
        for width in [280.0, 400, 620, 1000] {
            let next = snapshot()
            _ = next.columns.visibility(inListWidth: width)
            XCTAssertTrue(next === first)
        }
        XCTAssertFalse(first === snapshot(.nameAscending))
        let search = snapshot(.nameAscending, "Title")
        XCTAssertFalse(search === snapshot(.nameAscending, "absent"))
        XCTAssertTrue(snapshot(.nameAscending, "absent") === snapshot(.nameAscending, " absent "))
        let german = snapshot()
        defaults.set("en", forKey: "interfaceLanguage")
        let english = snapshot()
        XCTAssertFalse(german === english)
        XCTAssertNotEqual(german.rows["one"]?.description, english.rows["one"]?.description)
        cache.invalidate()
        XCTAssertFalse(english === snapshot())
    }
}
