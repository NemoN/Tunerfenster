import XCTest
@testable import Tunerfenster

private actor LibraryStub: RecordingLibraryAPI {
    var values: [SavedRecording]
    let delayed: Bool
    let refuseDeletion: Bool
    let keepAfterDeletion: Bool
    let roots: [RecordingStorage]
    let refuseRoots: Bool
    var deletions = [String]()
    var tickets = 0
    var progressWrites = [(String, RecordingCheckpoint)]()
    var refuseProgress = false
    func setRefuseProgress(_ value: Bool) { refuseProgress = value }
    init(_ values: [SavedRecording], delayed: Bool = false, refuseDeletion: Bool = false, keepAfterDeletion: Bool = false,
         roots: [RecordingStorage] = [], refuseRoots: Bool = false) {
        self.values = values; self.delayed = delayed
        self.refuseDeletion = refuseDeletion; self.keepAfterDeletion = keepAfterDeletion
        self.roots = roots; self.refuseRoots = refuseRoots
    }
    func setValues(_ values: [SavedRecording]) { self.values = values }
    func recordingStorageRoots() async throws -> [RecordingStorage] {
        if refuseRoots { throw AppError.message("missingPermissions") }
        return roots
    }
    func savedRecordings() async throws -> [SavedRecording] {
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        return values
    }
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL {
        tickets += 1
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        return URL(string: "http://localhost/dvrfile/\(recording.id)?ticket=fixture")!
    }
    func deleteRecording(uuid: String) async throws {
        deletions.append(uuid)
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        if refuseDeletion { throw AppError.message("missingPermissions") }
        if !keepAfterDeletion { values.removeAll { $0.id == uuid } }
    }
    func recordingProgress(uuid: String) async throws -> RecordingProgress {
        guard let item = values.first(where: { $0.id == uuid }) else { throw AppError.message("recordingFileUnavailable") }
        return item.progress
    }
    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress {
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        if refuseProgress { throw AppError.message("missingPermissions") }
        guard let index = values.firstIndex(where: { $0.id == uuid }) else { throw AppError.message("recordingFileUnavailable") }
        progressWrites.append((uuid, checkpoint))
        let state = checkpoint.applying(to: values[index].progress)
        values[index].playposition = state.playposition
        values[index].playcount = state.playcount
        return values[index].progress
    }
}

final class RecordingLibraryTests: XCTestCase {
    let id = String(repeating: "a", count: 32)

    @MainActor func testSelectingRecordingsOnlyShowsMetadataWithoutTicketsOrProgressWrites() async throws {
        var first = item(id)
        first.playposition = 120
        let second = item(String(repeating: "b", count: 32)), library = RecordingLibrary(), stub = LibraryStub([first, second])
        library.configure(stub); library.setActive(true); await library.refresh()
        library.select(first)
        XCTAssertEqual(library.selected?.id, first.id)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertFalse(library.opening)
        await library.updatePlayback()
        library.select(second)
        XCTAssertEqual(library.selected?.id, second.id)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertTrue(library.muted)
        let tickets = await stub.tickets, writes = await stub.progressWrites
        XCTAssertEqual(tickets, 0)
        XCTAssertTrue(writes.isEmpty)
        let unchanged = try await stub.recordingProgress(uuid: first.id)
        XCTAssertEqual(unchanged.position, 120)
        library.configure(nil)
    }

    @MainActor func testSameSelectionPreservesPlaybackButAnotherSelectionStopsWithoutStartingIt() async {
        let first = item(id), second = item(String(repeating: "b", count: 32)), library = RecordingLibrary()
        let stub = LibraryStub([first, second])
        library.configure(stub); library.setActive(true); await library.refresh()
        await library.play(first)
        XCTAssertTrue(library.playbackRequested)
        library.select(first)
        XCTAssertTrue(library.playbackRequested)
        library.select(second)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertEqual(library.selected?.id, second.id)
        let beforeExplicitPlay = await stub.tickets
        XCTAssertEqual(beforeExplicitPlay, 1)
        await library.play(second)
        XCTAssertTrue(library.playbackRequested)
        let afterExplicitPlay = await stub.tickets
        XCTAssertEqual(afterExplicitPlay, 2)
        library.configure(nil)
    }

    @MainActor func testBrowsingAnotherRecordingRejectsALateTicketFromThePreviousSelection() async {
        let first = item(id), second = item(String(repeating: "b", count: 32)), library = RecordingLibrary()
        library.configure(LibraryStub([first, second], delayed: true)); library.setActive(true); await library.refresh()
        let play = Task { await library.play(first) }
        for _ in 0..<100 where !library.opening { await Task.yield() }
        XCTAssertTrue(library.opening)
        library.select(second)
        await play.value
        XCTAssertEqual(library.selected?.id, second.id)
        XCTAssertFalse(library.opening)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertTrue(library.muted)
        library.configure(nil)
    }

    @MainActor func testExplicitPlaybackAfterSeveralSelectionsStartsOnlyTheChosenRecording() async {
        let first = item(id), second = item(String(repeating: "b", count: 32)), library = RecordingLibrary()
        let stub = LibraryStub([first, second], delayed: true)
        library.configure(stub); library.setActive(true); await library.refresh()
        library.select(first)
        library.select(second)
        await library.play(second)
        XCTAssertEqual(library.selected?.id, second.id)
        XCTAssertTrue(library.playbackRequested)
        XCTAssertFalse(library.muted)
        let tickets = await stub.tickets
        XCTAssertEqual(tickets, 1)
        library.configure(nil)
    }

    @MainActor func testUnavailableRecordingCanBeBrowsedAndRefreshedWithoutPlayback() async {
        var missing = item(id, size: 0)
        missing.disp_description = "Programme information"
        let library = RecordingLibrary(), stub = LibraryStub([missing])
        library.configure(stub); library.setActive(true); await library.refresh()
        library.select(missing)
        await library.refresh()
        XCTAssertEqual(library.selected?.detail, "Programme information")
        XCTAssertFalse(library.selected?.canPlay ?? true)
        XCTAssertFalse(library.playbackRequested)
        let tickets = await stub.tickets
        XCTAssertEqual(tickets, 0)
        library.configure(nil)
    }

    @MainActor func testExplicitUnwatchedOverridesAnInFlightCompletionAndStalePlaybackRead() async {
        let item = item(id), stub = LibraryStub([item], delayed: true), sync = RecordingProgressSync()
        sync.configure(stub, scope: nil)
        sync.enqueue(.init(position: 0, seen: true), for: item, force: true)
        try? await Task.sleep(for: .milliseconds(10))
        let oldRevision = sync.revision
        sync.enqueue(.init(position: 0, seen: false, seenOverride: false), for: item, force: true)
        sync.accept(.init(playposition: 300, playcount: 1), uuid: item.id, since: oldRevision)
        XCTAssertFalse(sync.state(for: item).seen)
        await sync.flush()
        let stored = try? await stub.recordingProgress(uuid: item.id)
        XCTAssertEqual(stored?.playcount, 0)
        XCTAssertEqual(stored?.position, 0)
        XCTAssertFalse(sync.state(for: item).seen)
        sync.configure(nil, scope: nil)
    }

    @MainActor func testLibraryMenuMarksAreSyncedAndInactiveOrStaleEntriesAreIgnored() async throws {
        var recording = item(id)
        recording.playcount = 7; recording.watched = 1_700_000_000; recording.playposition = 200
        let library = RecordingLibrary(), stub = LibraryStub([recording])
        XCTAssertFalse(library.canMarkSeen(recording))
        library.configure(stub); library.setActive(true); await library.refresh()
        XCTAssertTrue(library.canMarkSeen(recording))
        library.markSeen(false, for: recording)
        XCTAssertFalse(library.progress(for: recording).seen)
        XCTAssertEqual(library.progress(for: recording).position, 0)
        await library.retryProgressSync()
        let reset = try await stub.recordingProgress(uuid: id)
        XCTAssertEqual(reset.playcount, 0)
        XCTAssertFalse(reset.seen)
        library.markSeen(true, for: recording)
        await library.retryProgressSync()
        let marked = try await stub.recordingProgress(uuid: id)
        XCTAssertTrue(marked.seen)
        let unknown = item(String(repeating: "b", count: 32))
        XCTAssertFalse(library.canMarkSeen(unknown))
        library.configure(nil)
        XCTAssertFalse(library.canMarkSeen(recording))
    }

    @MainActor func testProgressSyncCoalescesInFlightWritesAndIgnoresStaleCatalogueResponses() async {
        let item = item(id), stub = LibraryStub([item], delayed: true), sync = RecordingProgressSync()
        sync.configure(stub, scope: nil)
        sync.merge([item], since: sync.revision)
        let oldRevision = sync.revision
        sync.enqueue(.init(position: 20, seen: false), for: item, force: true)
        try? await Task.sleep(for: .milliseconds(10))
        sync.enqueue(.init(position: 40, seen: true), for: item, force: true)
        sync.enqueue(.init(position: 60, seen: false), for: item, force: true)
        await sync.flush()
        let writes = await stub.progressWrites
        XCTAssertEqual(writes.map { $0.1.position }, [20, 60])
        XCTAssertEqual(writes.last?.1.seen, true)
        XCTAssertEqual(sync.state(for: item).position, 60)
        XCTAssertTrue(sync.state(for: item).seen)
        sync.merge([item], since: oldRevision)
        XCTAssertEqual(sync.state(for: item).position, 60, "A grid read started before the write must not restore its old position")
        var remote = item; remote.playposition = 90; remote.playcount = 1
        sync.merge([remote], since: sync.revision)
        XCTAssertEqual(sync.state(for: item).position, 90, "A later refresh adopts another client's changes")
        sync.configure(nil, scope: nil)
    }

    @MainActor func testProgressSyncKeepsOfflineCheckpointAcrossRelaunchAndRetriesWithoutChangingAnotherServer() async throws {
        let suite = "Tunerfenster.ProgressSyncTests.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = item(id), stub = LibraryStub([item]), sync = RecordingProgressSync(defaults: defaults)
        await stub.setRefuseProgress(true)
        sync.configure(stub, scope: "server-a")
        sync.enqueue(.init(position: 120, seen: false), for: item, force: true)
        await sync.flush()
        XCTAssertNotNil(sync.error)
        XCTAssertEqual(sync.state(for: item).position, 120)
        sync.configure(nil, scope: nil)
        let restored = RecordingProgressSync(defaults: defaults)
        restored.configure(stub, scope: "server-b")
        XCTAssertEqual(restored.state(for: item).position, 0)
        restored.configure(stub, scope: "server-a")
        XCTAssertEqual(restored.state(for: item).position, 120)
        await stub.setRefuseProgress(false)
        await restored.flush()
        XCTAssertNil(restored.error)
        let stored = try await stub.recordingProgress(uuid: id)
        XCTAssertEqual(stored.position, 120)
        XCTAssertTrue(RecordingProgressOutbox(defaults: defaults).load(scope: "server-a").isEmpty)
        restored.configure(nil, scope: nil)
    }

    @MainActor func testOldProgressResponseCannotUpdateNewConnectionAndDeletedEntriesDropPendingCheckpoints() async {
        let item = item(id), old = LibraryStub([item], delayed: true), new = LibraryStub([item]), sync = RecordingProgressSync()
        sync.configure(old, scope: nil)
        sync.enqueue(.init(position: 120, seen: false), for: item, force: true)
        try? await Task.sleep(for: .milliseconds(5))
        sync.configure(new, scope: nil)
        try? await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(sync.state(for: item).position, 0)
        let newWrites = await new.progressWrites
        XCTAssertTrue(newWrites.isEmpty)
        await new.setRefuseProgress(true)
        sync.enqueue(.init(position: 20, seen: false), for: item, force: true)
        await sync.flush()
        sync.merge([], since: sync.revision)
        await new.setRefuseProgress(false)
        await sync.flush()
        XCTAssertEqual(sync.state(for: item).position, 0)
        sync.configure(nil, scope: nil)
    }
    func item(_ name: String, state: String = "completed", size: Int64? = 100, start: Double = 1) -> SavedRecording {
        SavedRecording(uuid: name, disp_title: name, channelname: "QA Channel", start: start,
                       filesize: size, sched_status: state, url: "dvrfile/\(name)")
    }

    func testDVRTextAndFileStatesDoNotTreatTimersAsRecordings() throws {
        let data = Data(#"{"uuid":"abc","title":{"ger":"Testaufnahme","eng":"Test recording"},"description":{"eng":"Details"},"sched_status":"completedWarning","filesize":400,"url":"dvrfile/abc"}"#.utf8)
        let recorded = try JSONDecoder().decode(SavedRecording.self, from: data)
        XCTAssertNotEqual(recorded.name, L10n.text("untitledRecording"))
        XCTAssertEqual(recorded.detail, "Details")
        XCTAssertTrue(recorded.hasError)
        XCTAssertTrue(recorded.canPlay)
        XCTAssertTrue(recorded.matches("test"))
        XCTAssertFalse(recorded.matches("absent"))
        XCTAssertFalse(item("scheduled", state: "scheduled", size: 0).isExisting)
        XCTAssertFalse(item("missed", state: "missed", size: 0).isExisting)
        XCTAssertTrue(item("running", state: "recording").canPlay)
        XCTAssertTrue(item("partial", state: "completedError").canPlay)
        XCTAssertFalse(item("missing", size: 0).canPlay)
    }

    @MainActor func testLibraryFiltersTimersDeduplicatesAndSortsNewestFirst() async {
        let library = RecordingLibrary()
        library.configure(LibraryStub([item("old"), item("new", start: 50), item("old"), item("future", state: "scheduled", size: 0)]))
        library.setActive(true)
        await library.refresh()
        XCTAssertEqual(library.items.map(\.id), ["new", "old"])
        library.setActive(false)
    }

    @MainActor func testServerFolderMoveRefreshesSelectedMetadataWithoutReopeningPlayback() async {
        var recording = item(id)
        recording.filename = "/recordings/Old/episode.ts"
        recording.config_name = "default"
        let library = RecordingLibrary(), stub = LibraryStub([recording], roots: [.init(uuid: "default", storage: "/recordings")])
        library.configure(stub); library.setActive(true)
        await library.refresh(); await library.play(recording)
        XCTAssertEqual(library.folderTree.folders.map(\.name), ["Old"])
        recording.filename = "/recordings/New/episode.ts"
        await stub.setValues([recording])
        await library.refresh()
        XCTAssertEqual(library.folderTree.folders.map(\.name), ["New"])
        XCTAssertEqual(library.selected?.filename, recording.filename)
        XCTAssertEqual(library.selected?.id, id)
        let tickets = await stub.tickets
        XCTAssertEqual(tickets, 1)
        library.configure(nil)
        XCTAssertTrue(library.storageRoots.isEmpty)
    }

    @MainActor func testMissingProfilePermissionDoesNotHideRecordingsOrFolders() async {
        var recording = item(id)
        recording.filename = "/recordings/Crime/episode.ts"
        let library = RecordingLibrary(), stub = LibraryStub([recording], refuseRoots: true)
        library.configure(stub); library.setActive(true)
        await library.refresh()
        XCTAssertNil(library.error)
        XCTAssertEqual(library.items.map(\.id), [id])
        XCTAssertEqual(library.folderTree.folders.map(\.name), ["Crime"])
        library.configure(nil)
    }

    @MainActor func testListCacheRefreshesChangedMetadataAndRemovalWithoutChangingUUID() async throws {
        var recording = item(id)
        recording.filename = "/recordings/Old/episode.ts"
        let other = item("other"), library = RecordingLibrary(), stub = LibraryStub([recording, other])
        library.configure(stub); library.setActive(true)
        await library.refresh()
        let first = library.listSnapshot(sort: .dateNewest, search: "")
        library.toggleMute()
        XCTAssertTrue(first === library.listSnapshot(sort: .dateNewest, search: ""))
        recording.disp_title = "Changed title"; recording.duration = 7200
        recording.filename = "/recordings/New/episode.ts"
        await stub.setValues([recording])
        await library.refresh()
        let refreshed = library.listSnapshot(sort: .dateNewest, search: "")
        XCTAssertFalse(first === refreshed)
        XCTAssertEqual(refreshed.rows[id]?.fullName, "Changed title")
        XCTAssertEqual(refreshed.rows[id]?.duration, "2:00:00")
        XCTAssertTrue(try XCTUnwrap(refreshed.tree.paths[id]).contains("New"))
        XCTAssertNil(refreshed.rows[other.id])
        library.configure(nil)
        let empty = library.listSnapshot(sort: .dateNewest, search: "")
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertTrue(empty.rootEntries.isEmpty)
    }

    @MainActor func testDeletionRequiresConfirmationAndCancellationMakesNoRequest() async {
        let recording = item(id), library = RecordingLibrary()
        let stub = LibraryStub([recording])
        library.configure(stub); library.setActive(true)
        await library.refresh()
        XCTAssertNil(library.confirmDeletion())
        library.requestDeletion(recording)
        XCTAssertEqual(library.deletionCandidate?.id, id)
        library.cancelDeletion()
        XCTAssertNil(library.confirmDeletion())
        let requests = await stub.deletions
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(library.items.map(\.id), [id])
        library.configure(nil)
    }

    @MainActor func testConfirmedDeletionTargetsOneEntryAndPreservesOtherPlayback() async throws {
        let recording = item(id), other = item(String(repeating: "b", count: 32))
        let library = RecordingLibrary(), stub = LibraryStub([recording, other])
        var deleted = [String]()
        library.didDelete = { deleted.append($0) }
        library.configure(stub); library.setActive(true)
        await library.refresh()
        await library.play(other)
        library.requestDeletion(recording)
        let task = try XCTUnwrap(library.confirmDeletion())
        XCTAssertNil(library.confirmDeletion(), "A second click must not submit another deletion")
        await task.value
        let requests = await stub.deletions
        XCTAssertEqual(requests, [id])
        XCTAssertEqual(library.items.map(\.id), [other.id])
        XCTAssertEqual(library.selected?.id, other.id)
        XCTAssertNil(library.deletingID)
        XCTAssertNil(library.deletionError)

        library.requestDeletion(other)
        let playing = try XCTUnwrap(library.confirmDeletion())
        await playing.value
        XCTAssertNil(library.selected)
        XCTAssertFalse(library.opening)
        XCTAssertNil(library.playbackError)
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertEqual(deleted, [id, other.id])
        library.configure(nil)
    }

    @MainActor func testDeletionBlocksRunningTimersAndUnlistedOrMalformedEntries() async {
        let library = RecordingLibrary()
        let running = item(id, state: "recording")
        let timer = item(String(repeating: "b", count: 32), state: "scheduled", size: 0)
        let malformed = item("not-a-uuid")
        let missingFile = item(String(repeating: "c", count: 32), size: 0)
        let stub = LibraryStub([running, timer, malformed, missingFile])
        library.configure(stub); library.setActive(true)
        await library.refresh()
        for recording in [running, timer, malformed, item(String(repeating: "d", count: 32))] {
            XCTAssertFalse(library.canDelete(recording))
            library.requestDeletion(recording)
            XCTAssertNil(library.deletionCandidate)
        }
        XCTAssertTrue(library.canDelete(missingFile), "A finished entry with a missing file can still be removed")
        library.configure(nil)
    }

    @MainActor func testDeletionRefusalAndUnconfirmedSuccessKeepTheEntryAndSelection() async throws {
        for refuse in [false, true] {
            let recording = item(id), library = RecordingLibrary()
            let stub = LibraryStub([recording], refuseDeletion: refuse, keepAfterDeletion: true)
            library.configure(stub); library.setActive(true)
            await library.refresh(); await library.play(recording)
            library.requestDeletion(recording)
            let task = try XCTUnwrap(library.confirmDeletion())
            await task.value
            let requests = await stub.deletions
            XCTAssertEqual(requests, [id])
            XCTAssertEqual(library.items.map(\.id), [id])
            XCTAssertEqual(library.selected?.id, id)
            XCTAssertNotNil(library.deletionError)
            XCTAssertNil(library.deletingID)
            library.dismissDeletionError()
            XCTAssertNil(library.deletionError)
            library.configure(nil)
        }
    }

    @MainActor func testDeletionRevalidatesServerStateAndHandlesAlreadyDeletedEntry() async throws {
        let recording = item(id), library = RecordingLibrary(), stub = LibraryStub([item(id)])
        library.configure(stub); library.setActive(true)
        await library.refresh()
        library.requestDeletion(recording)
        await stub.setValues([item(id, state: "recording")])
        let changed = try XCTUnwrap(library.confirmDeletion())
        await changed.value
        XCTAssertNotNil(library.deletionError)
        let blocked = await stub.deletions
        XCTAssertTrue(blocked.isEmpty)
        XCTAssertEqual(library.items.map(\.id), [id])

        library.requestDeletion(recording)
        await stub.setValues([])
        let removedElsewhere = try XCTUnwrap(library.confirmDeletion())
        await removedElsewhere.value
        XCTAssertNil(library.deletionError)
        XCTAssertTrue(library.items.isEmpty)
        let requests = await stub.deletions
        XCTAssertTrue(requests.isEmpty, "A vanished UUID does not need another delete request")
        library.configure(nil)
    }

    @MainActor func testConnectionChangeOrLeavingModeInvalidatesDeletionBeforeWrite() async throws {
        for changeConnection in [false, true] {
            let recording = item(id), library = RecordingLibrary(), stub = LibraryStub([item(id)], delayed: true)
            library.configure(stub); library.setActive(true)
            await library.refresh()
            library.requestDeletion(recording)
            let task = try XCTUnwrap(library.confirmDeletion())
            if changeConnection { library.configure(nil) } else { library.setActive(false) }
            await task.value
            let requests = await stub.deletions
            XCTAssertTrue(requests.isEmpty)
            XCTAssertNil(library.deletionCandidate)
            XCTAssertNil(library.deletingID)
            XCTAssertNil(library.deletionError)
        }
    }

    @MainActor func testLeavingRecordingsRejectsLateTicketAndMutesPlayback() async {
        let library = RecordingLibrary(), recording = item(id)
        library.configure(LibraryStub([recording], delayed: true))
        library.setActive(true)
        let play = Task { await library.play(recording) }
        for _ in 0..<100 where !library.opening { await Task.yield() }
        XCTAssertTrue(library.opening)
        library.setActive(false)
        await play.value
        XCTAssertNil(library.selected)
        XCTAssertTrue(library.muted)
        XCTAssertFalse(library.opening)
        XCTAssertNil(library.playbackError)
    }

    @MainActor func testConnectionChangeDiscardsOldCatalogue() async {
        let library = RecordingLibrary()
        library.configure(LibraryStub([item("old-server")], delayed: true))
        library.setActive(true)
        let refresh = Task { await library.refresh() }
        for _ in 0..<100 where !library.loading { await Task.yield() }
        library.configure(LibraryStub([item("new-server")]))
        await refresh.value
        XCTAssertTrue(library.items.isEmpty)
        library.setActive(true)
        await library.refresh()
        XCTAssertEqual(library.items.map(\.id), ["new-server"])
        library.configure(nil)
    }

    @MainActor func testThirdModeStopsLiveTargetsKeepsAssignmentsAndRestoresTVTuner() throws {
        let suite = "TunerfensterRecordingMode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "fixture", password: "fixture")
        let monitor = Monitor(selectionStore: store, preferences: defaults)
        monitor.loadSelections(for: connection)
        let tuner = Tuner(input: Input(uuid: "a", input: "Tuner A"), previews: [], hasEPG: false, unresolvedTV: false)
        monitor.tuners = [tuner]; monitor.connected = true
        monitor.choose(StreamChoice(service: Service(uuid: "service"), name: "Channel", mapped: true, multiplex: nil), for: tuner)
        monitor.setViewingMode(.tv)
        XCTAssertEqual(monitor.focusedID, tuner.id)
        let assignments = monitor.savedManual
        monitor.setViewingMode(.recordings)
        XCTAssertEqual(monitor.viewingMode, .recordings)
        XCTAssertTrue(monitor.playbackTuners.isEmpty)
        XCTAssertEqual(monitor.liveCount, 0)
        XCTAssertNil(monitor.audioID)
        XCTAssertNil(monitor.focusedID)
        XCTAssertFalse(monitor.canSwitchFocusedChannel)
        monitor.focus(tuner.id)
        XCTAssertNil(monitor.focusedID)
        XCTAssertEqual(monitor.savedManual, assignments)
        let restarted = Monitor(selectionStore: store, preferences: defaults)
        restarted.loadSelections(for: connection)
        XCTAssertEqual(restarted.viewingMode, .recordings)
        XCTAssertTrue(restarted.playbackTuners.isEmpty)
        monitor.setViewingMode(.tv)
        XCTAssertEqual(monitor.focusedID, tuner.id)
        XCTAssertEqual(monitor.savedManual, assignments)
        monitor.shutdown(); restarted.shutdown()
    }
}

private final class LibraryURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class RecordingLibraryAPITests: XCTestCase {
    func testExplicitUnwatchedWritesZeroCounterWithoutTouchingReadonlyHistoryAndChecksReadback() async throws {
        let api = client(), uuid = String(repeating: "b", count: 32)
        defer { api.close(); LibraryURLProtocol.respond = nil }
        var position = 200, count = 3, writes = 0, accept = true
        LibraryURLProtocol.respond = { request in
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/tvh/api/idnode/save")
                let form = try self.form(request)
                let node = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(form["node"]).utf8)) as? [String: Any])
                XCTAssertEqual(Set(node.keys), ["uuid", "playposition", "playcount"])
                XCTAssertEqual(node["uuid"] as? String, uuid)
                if accept {
                    position = try XCTUnwrap(node["playposition"] as? Int)
                    count = try XCTUnwrap(node["playcount"] as? Int)
                }
                writes += 1
                return Data("{}".utf8)
            }
            return Data("{\"entries\":[{\"uuid\":\"\(uuid)\",\"sched_status\":\"completed\",\"playposition\":\(position),\"playcount\":\(count),\"watched\":1700000000}]}".utf8)
        }
        let cleared = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 0, seen: false, seenOverride: false))
        XCTAssertEqual(cleared.playcount, 0)
        XCTAssertEqual(cleared.position, 0)
        XCTAssertEqual(cleared.watched, 1_700_000_000, "Read-only history is not overwritten")
        XCTAssertFalse(cleared.seen)
        let watched = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 0, seen: true, seenOverride: true))
        XCTAssertTrue(watched.seen)
        accept = false
        do {
            _ = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 0, seen: false, seenOverride: false))
            XCTFail("An ignored unwatched mark must not be confirmed")
        } catch let error as AppError {
            guard case .message("recordingProgressUnconfirmed", _) = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertEqual(writes, 3)
    }

    private func form(_ request: URLRequest) throws -> [String: String] {
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = stream.read(&buffer, maxLength: buffer.count)
            data = Data(buffer.prefix(max(0, count)))
        }
        return Dictionary(uniqueKeysWithValues: (URLComponents(string: "http://localhost/?" + String(decoding: data, as: UTF8.self))?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testProgressUpdatesUsePartialWritesPreserveExistingSeenCountAndAreIdempotent() async throws {
        let api = client(), uuid = String(repeating: "b", count: 32)
        defer { api.close(); LibraryURLProtocol.respond = nil }
        var position = 0, count = 4, writes = 0
        LibraryURLProtocol.respond = { request in
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/tvh/api/idnode/load")
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first { $0.name == "uuid" }?.value, uuid)
                XCTAssertEqual(query.first { $0.name == "grid" }?.value, "1")
                return Data("{\"entries\":[{\"uuid\":\"\(uuid)\",\"sched_status\":\"completed\",\"playposition\":\(position),\"playcount\":\(count),\"watched\":0}]}".utf8)
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/tvh/api/idnode/save")
            XCTAssertNil(request.url?.query)
            let form = try self.form(request)
            XCTAssertEqual(Set(form.keys), ["node"])
            let node = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(form["node"]).utf8)) as? [String: Any])
            XCTAssertEqual(node["uuid"] as? String, uuid)
            XCTAssertEqual(Set(node.keys), writes == 0 ? ["uuid", "playposition"] : ["uuid", "playposition", "playcount"])
            position = try XCTUnwrap(node["playposition"] as? Int)
            if let value = node["playcount"] as? Int { count = value }
            writes += 1
            return Data("{}".utf8)
        }
        let partial = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 120, seen: false))
        XCTAssertEqual(partial.position, 120); XCTAssertEqual(partial.playcount, 4)
        for _ in 0..<2 {
            let seen = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 0, seen: true))
            XCTAssertEqual(seen.position, 0); XCTAssertEqual(seen.playcount, 4)
        }
        XCTAssertEqual(writes, 3)
        for (id, position) in [("abc", 120), (uuid, -1), (uuid, Int(UInt32.max) + 1)] {
            do { _ = try await api.saveRecordingProgress(uuid: id, checkpoint: .init(position: position, seen: true)); XCTFail("Invalid updates must not be sent") }
            catch { XCTAssertTrue(error is AppError) }
        }
        XCTAssertEqual(writes, 3)
    }

    func testProgressUpdateVerifiesReadbackAndRejectsUnrelatedNodes() async throws {
        let api = client(), uuid = String(repeating: "b", count: 32)
        defer { api.close(); LibraryURLProtocol.respond = nil }
        var writes = 0, recording = true
        LibraryURLProtocol.respond = { request in
            if request.httpMethod == "POST" { writes += 1; return Data("{}".utf8) }
            let state = recording ? ",\"sched_status\":\"completed\"" : ""
            return Data("{\"entries\":[{\"uuid\":\"\(uuid)\"\(state),\"playposition\":0,\"playcount\":0}]}".utf8)
        }
        do {
            _ = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 60, seen: false))
            XCTFail("Ignored changes must not be reported as saved")
        } catch let error as AppError {
            guard case .message("recordingProgressUnconfirmed", _) = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertEqual(writes, 1)
        recording = false
        do {
            _ = try await api.saveRecordingProgress(uuid: uuid, checkpoint: .init(position: 60, seen: true))
            XCTFail("A tuner or other idnode must never be modified")
        } catch { XCTAssertTrue(error is AppError) }
        XCTAssertEqual(writes, 1)
    }

    func client() -> API {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryURLProtocol.self]
        return API(connection: Connection(address: "http://localhost:9981/tvh", username: "fixture", password: "fixture"), configuration: configuration)
    }

    func testStorageRootsAreReadFromRecordingProfilesWithoutWrites() async throws {
        let api = client()
        defer { api.close(); LibraryURLProtocol.respond = nil }
        LibraryURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/tvh/api/dvr/config/grid")
            return Data(#"{"entries":[{"uuid":"profile","storage":"/recordings"}],"total":1}"#.utf8)
        }
        let roots = try await api.recordingStorageRoots()
        XCTAssertEqual(roots.first?.uuid, "profile")
        XCTAssertEqual(roots.first?.storage, "/recordings")
    }

    func testDeletionPostsOneValidatedUUIDWithServerWebrootAndNoQuery() async throws {
        let api = client(), uuid = String(repeating: "b", count: 32)
        defer { api.close(); LibraryURLProtocol.respond = nil }
        var posts = 0
        LibraryURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/tvh/api/idnode/delete")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.url?.user)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&buffer, maxLength: buffer.count)
                data = Data(buffer.prefix(max(0, count)))
            }
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "uuid=\(uuid)")
            posts += 1
            return Data(#"{"success":1}"#.utf8)
        }
        try await api.deleteRecording(uuid: uuid)
        for invalid in ["", "abc", uuid + "," + uuid, String(repeating: "x", count: 32)] {
            do { try await api.deleteRecording(uuid: invalid); XCTFail("Reject malformed or multiple UUIDs") }
            catch { XCTAssertTrue(error is AppError) }
        }
        XCTAssertEqual(posts, 1)
    }

    func testGridUsesPaginationAndOnlyReadRequests() async throws {
        let api = client()
        defer { api.close(); LibraryURLProtocol.respond = nil }
        var offsets = [String]()
        LibraryURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/tvh/api/dvr/entry/grid")
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "start" }!.value!
            offsets.append(offset)
            return Data("{\"entries\":[{\"uuid\":\"\(offset)\"}],\"total\":2}".utf8)
        }
        let items = try await api.savedRecordings()
        XCTAssertEqual(items.map(\.uuid), ["0", "1"])
        XCTAssertEqual(offsets, ["0", "1"])
    }

    func testTicketKeepsServerWebrootAndRejectsWrongRecordingOrOrigin() async throws {
        let api = client(), id = String(repeating: "b", count: 32)
        defer { api.close(); LibraryURLProtocol.respond = nil }
        let recording = SavedRecording(uuid: id, filesize: 100, sched_status: "completed", url: "https://evil.invalid/file")
        var playlist = "http://localhost:9981/tvh/dvrfile/\(id)?ticket=fixture"
        LibraryURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/tvh/play/ticket/dvrfile/\(id)")
            XCTAssertNil(request.url?.user)
            return Data("#EXTM3U\n\(playlist)\n".utf8)
        }
        let url = try await api.recordingTicketURL(for: recording)
        XCTAssertEqual(url.path, "/tvh/dvrfile/\(id)")
        XCTAssertNil(url.password)
        for invalid in ["http://localhost:9981/tvh/dvrfile/other?ticket=fixture", "http://evil.invalid/dvrfile/\(id)?ticket=fixture"] {
            playlist = invalid
            do { _ = try await api.recordingTicketURL(for: recording); XCTFail("Must reject mismatched DVR endpoints") }
            catch { XCTAssertTrue(error is AppError) }
        }
    }
}
