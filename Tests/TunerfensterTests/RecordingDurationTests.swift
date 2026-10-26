import XCTest
import Combine
@testable import Tunerfenster

private actor DurationLibraryStub: RecordingLibraryAPI {
    var items: [SavedRecording]
    let durations: [String: Double]
    let delay: Bool
    let fail: Bool
    var durationCalls = 0
    var tickets = 0
    var writes = 0

    init(_ items: [SavedRecording], durations: [String: Double], delay: Bool = false, fail: Bool = false) {
        self.items = items; self.durations = durations; self.delay = delay; self.fail = fail
    }
    func savedRecordings() async throws -> [SavedRecording] { items }
    func setItems(_ values: [SavedRecording]) { items = values }
    func recordingStorageRoots() async throws -> [RecordingStorage] { [] }
    func recordingFileDurations(for recordings: [SavedRecording], endpoint: CommercialEndpoint) async throws -> [String: Double] {
        durationCalls += 1
        if delay { try? await Task.sleep(for: .milliseconds(60)) }
        if fail { throw AppError.message("commercialAccessDenied") }
        return durations
    }
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL {
        tickets += 1
        return URL(string: "http://localhost/dvrfile/fixture")!
    }
    func deleteRecording(uuid: String) async throws {}
    func recordingProgress(uuid: String) async throws -> RecordingProgress { .init(playposition: 0, playcount: 0) }
    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress {
        writes += 1
        return .init(playposition: 0, playcount: 0)
    }
}

final class RecordingDurationTests: XCTestCase {
    private let nfl = String(repeating: "a", count: 32)
    private let ninja = String(repeating: "b", count: 32)

    private func recording(_ id: String, scheduled: Double) -> SavedRecording {
        .init(uuid: id, disp_title: id == nfl ? "NFL LIVE" : "Ninja Warrior Germany", start: 100,
              stop: 100 + scheduled, duration: scheduled, filesize: 1000, sched_status: "completed")
    }

    func testLateStartFileDurationsOverrideTheWholeScheduledProgramme() {
        var football = recording(nfl, scheduled: 14100)
        football.fileDuration = 6757
        var ninja = recording(self.ninja, scheduled: 10800)
        ninja.fileDuration = 32
        XCTAssertEqual(football.compactDurationLabel, "1:52:37")
        XCTAssertEqual(ninja.compactDurationLabel, "0:00:32")
        XCTAssertEqual(RecordingSort.durationShortest.sorted([football, ninja]).map(\.id), [self.ninja, nfl])
    }

    func testMetadataBatchOnlyUsesConfirmedRecordingIdentitiesAndValidFileClocks() {
        let football = recording(nfl, scheduled: 14100), ninja = recording(self.ninja, scheduled: 10800)
        let files: (Int64) -> HTSPValue = { duration in
            .list([.map(["start": .integer(1000), "stop": .integer(1000 + duration)])])
        }
        let metadata: [[String: HTSPValue]] = [
            ["idStr": .string(nfl), "id": .integer(1), "files": files(6757)],
            ["idStr": .string(self.ninja), "id": .integer(2), "files": files(32)],
            ["idStr": .string(String(repeating: "c", count: 32)), "id": .integer(3), "files": files(999)]
        ]
        XCTAssertEqual(HTSPCommercials.fileDurations(recordings: [football, ninja], metadata: metadata), [nfl: 6757, self.ninja: 32])
        XCTAssertTrue(HTSPCommercials.fileDurations(recordings: [football], metadata: Array(metadata.dropFirst())).isEmpty)
        XCTAssertTrue(HTSPCommercials.fileDurations(recordings: [football], metadata: metadata + [metadata[0]]).isEmpty)
        var invalid = metadata[0]
        invalid["files"] = files(-5)
        XCTAssertTrue(HTSPCommercials.fileDurations(recordings: [football], metadata: [invalid]).isEmpty)
    }

    @MainActor func testListSelectionAndSortShareCachedDurationsWithoutPlaybackOrProgressWrites() async throws {
        let football = recording(nfl, scheduled: 14100), ninja = recording(self.ninja, scheduled: 10800)
        let library = RecordingLibrary(), stub = DurationLibraryStub([football, ninja], durations: [nfl: 6757, self.ninja: 32])
        library.configure(stub); library.setActive(true); await library.refresh()
        library.select(ninja)
        let before = library.listSnapshot(sort: .durationShortest, search: "")
        await library.loadFileDurations(force: true)?.value
        let snapshot = library.listSnapshot(sort: .durationShortest, search: "")
        XCTAssertFalse(before === snapshot)
        XCTAssertEqual(snapshot.rows[nfl]?.duration, "1:52:37")
        XCTAssertEqual(snapshot.rows[self.ninja]?.duration, "0:00:32")
        XCTAssertEqual(library.selected?.recordedDuration, 32)
        XCTAssertEqual(snapshot.rootEntries.map(\.id), ["recording/\(self.ninja)", "recording/\(nfl)"])
        let calls = await stub.durationCalls
        await library.refresh()
        XCTAssertNil(library.loadFileDurations())
        let afterCalls = await stub.durationCalls, tickets = await stub.tickets, writes = await stub.writes
        XCTAssertEqual(calls, afterCalls)
        XCTAssertEqual(library.listSnapshot(sort: .durationShortest, search: "").rows[self.ninja]?.duration, "0:00:32")
        XCTAssertEqual(tickets, 0); XCTAssertEqual(writes, 0)
        XCTAssertFalse(library.playbackRequested)
        library.configure(nil)
    }

    @MainActor func testOldConnectionCannotReplaceNewServerFileDurations() async {
        let item = recording(nfl, scheduled: 14100), library = RecordingLibrary()
        let old = DurationLibraryStub([item], durations: [nfl: 6757], delay: true)
        library.configure(old); library.setActive(true); await library.refresh()
        let pending = library.loadFileDurations(force: true)
        await Task.yield()
        let fresh = DurationLibraryStub([item], durations: [nfl: 32])
        library.configure(fresh); library.setActive(true); await library.refresh()
        await library.loadFileDurations(force: true)?.value
        await pending?.value
        XCTAssertEqual(library.items.first?.recordedDuration, 32)
        library.configure(nil)
        XCTAssertTrue(library.items.isEmpty)
    }

    @MainActor func testMetadataAccessFailureKeepsTheHTTPRecordingListAvailable() async {
        let item = recording(nfl, scheduled: 14100), library = RecordingLibrary()
        let stub = DurationLibraryStub([item], durations: [:], fail: true)
        library.configure(stub); library.setActive(true); await library.refresh()
        await library.loadFileDurations(force: true)?.value
        XCTAssertEqual(library.items.map(\.id), [nfl])
        XCTAssertNil(library.error)
        XCTAssertFalse(library.loading)
        library.configure(nil)
    }

    @MainActor func testBackgroundRefreshKeepsAnUnchangedListStableAndAppliesRealChanges() async {
        let item = recording(nfl, scheduled: 14100)
        let library = RecordingLibrary(), stub = DurationLibraryStub([item], durations: [:])
        library.configure(stub); library.setActive(true); await library.refresh()
        library.select(item)
        await library.loadCommercials(force: true)?.value
        await library.loadFileDurations(force: true)?.value
        let snapshot = library.listSnapshot(sort: .dateNewest, search: "")
        var notifications = 0
        let observer = library.objectWillChange.sink { notifications += 1 }

        await library.refresh(background: true)
        XCTAssertFalse(library.loading)
        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(snapshot === library.listSnapshot(sort: .dateNewest, search: ""))
        XCTAssertEqual(library.selected?.id, item.id)

        var changed = item
        changed.disp_title = "Updated title"
        await stub.setItems([changed, recording(ninja, scheduled: 10800)])
        await library.refresh(background: true)
        XCTAssertGreaterThan(notifications, 0)
        XCTAssertEqual(library.selected?.name, "Updated title")
        XCTAssertEqual(library.items.count, 2)
        XCTAssertFalse(snapshot === library.listSnapshot(sort: .dateNewest, search: ""))
        observer.cancel()
        library.configure(nil)
    }
}
