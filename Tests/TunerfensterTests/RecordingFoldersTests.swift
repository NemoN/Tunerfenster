import XCTest
@testable import Tunerfenster

final class RecordingFoldersTests: XCTestCase {
    private let roots = [RecordingStorage(uuid: "default", storage: "/library/recordings")]

    private func recording(_ id: String, path: String?, directory: String? = nil, profile: String = "default") -> SavedRecording {
        SavedRecording(uuid: id, disp_title: "Programme \(id)", filesize: 100, sched_status: "completed",
                       filename: path, directory: directory, config_name: profile)
    }

    func testActualServerFilenameOverridesOldTimerDirectory() throws {
        let item = try JSONDecoder().decode(SavedRecording.self, from: Data(#"{"uuid":"one","filename":"/library/recordings/Crime/episode.ts","directory":"Old folder","config_name":"default","sched_status":"completed","filesize":100}"#.utf8))
        let tree = RecordingFolderTree(items: [item], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["Crime"])
        XCTAssertEqual(tree.folders.first?.recordings.map(\.id), ["one"])
        XCTAssertEqual(tree.paths["one"], "Crime")
        XCTAssertTrue(tree.unfiled.isEmpty)
    }

    func testNestedFoldersCountAllDescendantsAndKeepCatalogueOrder() {
        let items = [recording("new", path: "/library/recordings/Series/Season 2/new.ts"),
                     recording("root", path: "/library/recordings/Series/root.ts"),
                     recording("old", path: "/library/recordings/Series/Season 2/old.ts"),
                     recording("other", path: "/library/recordings/Films/movie.ts")]
        let tree = RecordingFolderTree(items: items, storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["Films", "Series"])
        XCTAssertEqual(tree.folders.map(\.count), [1, 3])
        let series = tree.folders[1]
        XCTAssertEqual(series.recordings.map(\.id), ["root"])
        XCTAssertEqual(series.folders.first?.recordings.map(\.id), ["new", "old"])
        XCTAssertEqual(tree.paths["new"], "Series / Season 2")
        XCTAssertEqual(tree.ancestors["new"], [series.id, series.folders[0].id])
    }

    func testRootFilesAndMissingPathMetadataRemainAvailable() {
        let items = [recording("root", path: "/library/recordings/root.ts"), recording("unknown", path: nil)]
        let tree = RecordingFolderTree(items: items, storageRoots: roots)
        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertEqual(tree.unfiled.map(\.id), ["root", "unknown"])
        XCTAssertEqual(tree.paths["root"], "")
        XCTAssertNil(tree.paths["unknown"])
    }

    func testRootFilesStayDirectEvenWithSeveralStorageProfiles() {
        let roots = [RecordingStorage(uuid: "a", name: "First disk", storage: "/one/recordings"),
                     RecordingStorage(uuid: "b", name: "Second disk", storage: "/two/recordings")]
        let items = [recording("a1", path: "/one/recordings/a1.ts", profile: "a"),
                     recording("a2", path: "/one/recordings/a2.ts", profile: "a"),
                     recording("b1", path: "/two/recordings/b1.ts", profile: "b"),
                     recording("b2", path: "/two/recordings/b2.ts", profile: "b")]
        let tree = RecordingFolderTree(items: items, storageRoots: roots).flatteningSingleRecordingFolders()
        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertEqual(tree.unfiled.map(\.id), items.map(\.id))
        XCTAssertEqual(tree.paths["a1"], "First disk")
        XCTAssertEqual(tree.paths["b1"], "Second disk")
        XCTAssertNil(tree.ancestors["a1"])
    }

    func testSingleRecordingFoldersAndWholeSingleRecordingChainsBecomeDirectRows() {
        let items = [recording("single", path: "/library/recordings/Film/one.ts"),
                     recording("nested", path: "/library/recordings/Series/Season 1/episode.ts"),
                     recording("root", path: "/library/recordings/root.ts"),
                     recording("unknown", path: nil)]
        let source = RecordingFolderTree(items: items, storageRoots: roots)
        let tree = source.flatteningSingleRecordingFolders().sorted(using: .nameAscending)
        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertEqual(tree.unfiled.map(\.id), ["nested", "root", "single", "unknown"])
        XCTAssertEqual(Set(tree.unfiled.map(\.id)).count, items.count)
        XCTAssertEqual(tree.paths, source.paths)
        XCTAssertEqual(tree.paths["nested"], "Series / Season 1")
        XCTAssertEqual(tree.ancestors["single"], [])
        XCTAssertEqual(tree.ancestors["nested"], [])
        XCTAssertEqual(source.folders.count, 2, "The server hierarchy remains available independently of its presentation")
    }

    func testOnlySingleRecordingChildrenDisappearInsideMultiRecordingFolders() throws {
        let items = [recording("a", path: "/library/recordings/Series/Season 1/a.ts"),
                     recording("b", path: "/library/recordings/Series/Season 2/b.ts"),
                     recording("c", path: "/library/recordings/Series/Season 3/c.ts"),
                     recording("d", path: "/library/recordings/Series/Season 3/d.ts"),
                     recording("e", path: "/library/recordings/Series/e.ts")]
        let source = RecordingFolderTree(items: items, storageRoots: roots)
        let tree = source.flatteningSingleRecordingFolders().sorted(using: .nameAscending)
        let series = try XCTUnwrap(tree.folders.first)
        XCTAssertEqual(series.id, source.folders.first?.id)
        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series.recordings.map(\.id), ["a", "b", "e"])
        XCTAssertEqual(series.folders.map(\.name), ["Season 3"])
        XCTAssertEqual(series.folders.first?.recordings.map(\.id), ["c", "d"])
        XCTAssertEqual(tree.ancestors["a"], [series.id])
        XCTAssertEqual(tree.ancestors["c"], source.ancestors["c"])
        XCTAssertTrue(tree.unfiled.isEmpty)
    }

    func testFolderDisappearsAtOneRecordingAndReturnsWithTheSameIdentifier() throws {
        let one = recording("one", path: "/library/recordings/Crime/one.ts")
        let two = recording("two", path: "/library/recordings/Crime/two.ts")
        let multiple = RecordingFolderTree(items: [one, two], storageRoots: roots).flatteningSingleRecordingFolders()
        let id = try XCTUnwrap(multiple.folders.first?.id)
        let single = RecordingFolderTree(items: [two], storageRoots: roots).flatteningSingleRecordingFolders()
        XCTAssertTrue(single.folders.isEmpty)
        XCTAssertEqual(single.unfiled.map(\.id), ["two"])
        XCTAssertEqual(single.ancestors["two"], [])
        let restored = RecordingFolderTree(items: [two, one], storageRoots: roots).flatteningSingleRecordingFolders()
        XCTAssertEqual(restored.folders.first?.id, id)
        XCTAssertEqual(restored.ancestors["two"], [id])
    }

    func testDirectoryAndSegmentedFileMetadataAreFallbacks() {
        var segmented = recording("segments", path: nil)
        segmented.files = [RecordingFile(filename: ""), RecordingFile(filename: "/library/recordings/News/part.ts")]
        let tree = RecordingFolderTree(items: [segmented, recording("relative", path: nil, directory: "News")], storageRoots: [])
        XCTAssertEqual(tree.folders.reduce(0) { $0 + $1.count }, 2)
        XCTAssertTrue(tree.unfiled.isEmpty)
        XCTAssertTrue(tree.paths.values.allSatisfy { $0.contains("News") })
    }

    func testUnavailableProfilesInferSharedRootButKeepSingleFolderName() {
        let first = recording("one", path: "/library/recordings/Crime/one.ts")
        let second = recording("two", path: "/library/recordings/Science/two.ts")
        let multiple = RecordingFolderTree(items: [first, second], storageRoots: [])
        XCTAssertEqual(multiple.folders.map(\.name), ["Crime", "Science"])
        let single = RecordingFolderTree(items: [first], storageRoots: [])
        XCTAssertEqual(single.folders.map(\.name), ["Crime"])
    }

    func testRelativeDirectoryUsesItsProfileAndJoinsTheActualFolder() {
        let tree = RecordingFolderTree(items: [recording("absolute", path: "/library/recordings/News/episode.ts"),
                                               recording("relative", path: nil, directory: "News")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["News"])
        XCTAssertEqual(tree.folders.first?.count, 2)
        XCTAssertEqual(tree.paths["relative"], "News")
        XCTAssertEqual(tree.ancestors["absolute"], tree.ancestors["relative"])
    }

    func testStoragePrefixMustMatchWholeComponents() {
        let tree = RecordingFolderTree(items: [recording("one", path: "/library/recordings-other/Crime/one.ts")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["Crime"])
        XCTAssertEqual(tree.paths["one"], "Crime")
    }

    func testDifferentStorageRootsDoNotMergeIdenticallyNamedFolders() {
        let roots = [RecordingStorage(uuid: "a", name: "First disk", storage: "/one/recordings"),
                     RecordingStorage(uuid: "b", name: "Second disk", storage: "/two/recordings")]
        let tree = RecordingFolderTree(items: [recording("one", path: "/one/recordings/Crime/a.ts", profile: "a"),
                                               recording("two", path: "/two/recordings/Crime/b.ts", profile: "b")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["First disk", "Second disk"])
        XCTAssertEqual(tree.folders.map(\.count), [1, 1])
        XCTAssertNotEqual(tree.folders[0].folders[0].id, tree.folders[1].folders[0].id)
    }

    func testDuplicateStorageNamesAreDistinguishedByTheirPaths() {
        let roots = [RecordingStorage(uuid: "a", storage: "/one/recordings"), RecordingStorage(uuid: "b", storage: "/two/recordings")]
        let tree = RecordingFolderTree(items: [recording("one", path: "/one/recordings/Crime/a.ts", profile: "a"),
                                               recording("two", path: "/two/recordings/Crime/b.ts", profile: "b")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["/one/recordings", "/two/recordings"])
    }

    func testNestedProfileStorageIsStrippedUsingItsOwnProfile() {
        let roots = [RecordingStorage(uuid: "default", storage: "/library"),
                     RecordingStorage(uuid: "nested", storage: "/library/private")]
        let tree = RecordingFolderTree(items: [recording("one", path: "/library/private/Crime/a.ts", profile: "nested")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["Crime"])
    }

    func testServerPathNormalizationPreservesLiteralUnicodePercentAndBackslash() {
        let tree = RecordingFolderTree(items: [recording("one", path: "/library//recordings/./old/../Krimi %2F \\ Doku/ä.ts")], storageRoots: roots)
        XCTAssertEqual(tree.folders.map(\.name), ["Krimi %2F \\ Doku"])
        XCTAssertEqual(tree.paths["one"], "Krimi %2F \\ Doku")
    }

    func testMovingRecordingUpdatesFolderAndKeepsOtherFolderIdentifiersStable() {
        let old = RecordingFolderTree(items: [recording("move", path: "/library/recordings/Old/a.ts"),
                                              recording("stay", path: "/library/recordings/Stable/b.ts")], storageRoots: roots)
        let new = RecordingFolderTree(items: [recording("move", path: "/library/recordings/New/a.ts"),
                                              recording("stay", path: "/library/recordings/Stable/b.ts")], storageRoots: roots)
        XCTAssertEqual(new.paths["move"], "New")
        XCTAssertEqual(old.ancestors["stay"], new.ancestors["stay"])
        XCTAssertFalse(new.folders.contains { $0.name == "Old" })
    }
}
