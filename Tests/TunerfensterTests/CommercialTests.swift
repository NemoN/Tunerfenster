import XCTest
@testable import Tunerfenster

private actor CommercialLibraryStub: RecordingLibraryAPI {
    let recordings: [SavedRecording]
    var calls = 0
    var fail = false
    var delay = false
    init(_ recordings: [SavedRecording]) { self.recordings = recordings }
    func set(fail: Bool = false, delay: Bool = false) { self.fail = fail; self.delay = delay }
    func savedRecordings() async throws -> [SavedRecording] { recordings }
    func recordingStorageRoots() async throws -> [RecordingStorage] { [] }
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL { URL(string: "http://localhost/fixture")! }
    func deleteRecording(uuid: String) async throws {}
    func recordingProgress(uuid: String) async throws -> RecordingProgress { .init(playposition: 0, playcount: 0) }
    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress { .init(playposition: 0, playcount: 0) }
    func commercialData(for recording: SavedRecording, endpoint: CommercialEndpoint) async throws -> RecordingCommercialData {
        calls += 1
        if delay { try? await Task.sleep(for: .milliseconds(50)) }
        if fail { throw AppError.message("commercialAccessDenied") }
        return .init(breaks: [.init(start: recording.start ?? 10, end: (recording.start ?? 10) + 20)], fileDuration: 100)
    }
}

final class CommercialTests: XCTestCase {
    func testNormalizationRejectsInvalidRangesAndMergesOverlapsWithoutRemovingGaps() {
        let result = CommercialBreak.normalized([
            .init(start: 50, end: 70), .init(start: 10, end: 20), .init(start: 15, end: 30),
            .init(start: 10, end: 20), .init(start: 30, end: 40), .init(start: 41, end: 45),
            .init(start: -.infinity, end: 2), .init(start: -1, end: 5), .init(start: .nan, end: 8),
            .init(start: 1, end: .infinity), .init(start: 9, end: 9), .init(start: 10, end: 8)
        ])
        XCTAssertEqual(result, [.init(start: 10, end: 40), .init(start: 41, end: 45), .init(start: 50, end: 70)])
    }

    func testAutoSkipRunsOnceButManualSkipStillWorksAfterSeekingBack() {
        let breaks = [CommercialBreak(start: 10, end: 20), .init(start: 40, end: 50)]
        var state = CommercialSkipState()
        XCTAssertNil(state.target(position: 9.9, duration: 100, breaks: breaks, automatic: true))
        XCTAssertEqual(state.target(position: 10, duration: 100, breaks: breaks, automatic: true), 20)
        XCTAssertNil(state.target(position: 11, duration: 100, breaks: breaks, automatic: true))
        XCTAssertNil(state.target(position: 20, duration: 100, breaks: breaks, automatic: true))
        state.userSeek(to: 12, breaks: breaks)
        XCTAssertNil(state.target(position: 12, duration: 100, breaks: breaks, automatic: true))
        XCTAssertEqual(state.target(position: 12, duration: 100, breaks: breaks, automatic: false), 20)
        state.userSeek(to: 42, breaks: breaks)
        XCTAssertNil(state.target(position: 42, duration: 100, breaks: breaks, automatic: true))
        var replay = CommercialSkipState()
        XCTAssertEqual(replay.target(position: 42, duration: 100, breaks: breaks, automatic: true), 50)
    }

    func testSkipAndTimelineClipToDurationWithoutAcceptingInvalidValues() {
        let item = CommercialBreak(start: 10, end: 30)
        XCTAssertEqual(item.fractions(duration: 20), 0.5...1)
        XCTAssertNil(item.fractions(duration: 0))
        XCTAssertNil(item.fractions(duration: 10))
        XCTAssertNil(CommercialBreak(start: 10, end: -1).fractions(duration: 20))
        var state = CommercialSkipState()
        XCTAssertNil(state.target(position: .nan, duration: 20, breaks: [item], automatic: true))
        XCTAssertNil(state.target(position: 12, duration: 0, breaks: [item], automatic: true))
        XCTAssertEqual(state.target(position: 12, duration: 20, breaks: [item], automatic: true), 20)
    }

    func testCodecMatchesTVHeadendWireFormatRatherThanOnlyRoundtripping() throws {
        let packet = try HTSPCodec.encode(["id": .integer(0x12345678)])
        XCTAssertEqual(Array(packet), [0, 0, 0, 12, 2, 2, 0, 0, 0, 4, 105, 100, 0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(try HTSPCodec.decode(Data(packet.dropFirst(4))), ["id": .integer(0x12345678)])
        let zero = try HTSPCodec.encode(["id": .integer(0)])
        XCTAssertEqual(Array(zero.suffix(8)), [2, 2, 0, 0, 0, 0, 105, 100])
        let digest = HTSPCommercials.digest(password: "fixture-password", challenge: Data(0..<32))
        XCTAssertEqual(digest.map { String(format: "%02x", $0) }.joined(), "7ba4456b615effa887a07bd6126f7eef8f9447d8")
    }

    func testCodecRejectsTruncationDuplicateFieldsExcessiveIntegersAndRecursion() throws {
        let packet = try HTSPCodec.encode(["id": .integer(42)])
        let body = Data(packet.dropFirst(4))
        for count in 1..<body.count { XCTAssertThrowsError(try HTSPCodec.decode(Data(body.prefix(count)))) }
        XCTAssertThrowsError(try HTSPCodec.decode(body + body))
        XCTAssertThrowsError(try HTSPCodec.decode(Data([2, 1, 0, 0, 0, 9, 120] + Array(repeating: 0, count: 9))))
        XCTAssertThrowsError(try HTSPCodec.decode(Data([3, 0, 0, 0, 0, 0])))
        var nested = HTSPValue.integer(1)
        for _ in 0..<15 { nested = .map(["child": nested]) }
        let deep = try HTSPCodec.encode(["root": nested])
        XCTAssertThrowsError(try HTSPCodec.decode(Data(deep.dropFirst(4))))
    }

    func testHTSPCutAndCommercialActionsBecomeSecondsButMuteAndScenesDoNot() throws {
        func point(_ start: Int64, _ end: Int64, _ type: Int64) -> HTSPValue {
            .map(["start": .integer(start), "end": .integer(end), "type": .integer(type)])
        }
        let response: [String: HTSPValue] = ["cutpoints": .list([
            point(10_500, 20_750, 3), point(20_000, 30_000, 0), point(40_000, 50_000, 1),
            point(60_000, 70_000, 2), point(-1, 4, 3), point(10, 2, 3), point(90_000, 100_000, 9)
        ])]
        let encoded = try HTSPCodec.encode(response)
        XCTAssertEqual(try HTSPCommercials.breaks(HTSPCodec.decode(Data(encoded.dropFirst(4)))), [.init(start: 10.5, end: 30)])
        XCTAssertEqual(try HTSPCommercials.breaks([:]), [])
        XCTAssertThrowsError(try HTSPCommercials.breaks(["cutpoints": .string("invalid")]))
    }

    func testDVRIdentityUsesFullUUIDAndValidatesLegacyShortUUIDAgainstMetadata() throws {
        let item = SavedRecording(uuid: "12345678000000000000000000000000", channelname: "Fixture TV", start: 100, stop: 200)
        let base: [String: HTSPValue] = ["id": .integer(0x78563412), "start": .integer(100), "stop": .integer(200), "channelName": .string("Fixture TV")]
        XCTAssertEqual(try HTSPCommercials.recordingID(item, metadata: [base]), 0x78563412)
        var big = base; big["id"] = .integer(0x12345678)
        XCTAssertEqual(try HTSPCommercials.recordingID(item, metadata: [big]), 0x12345678)
        var wrong = base; wrong["start"] = .integer(99)
        XCTAssertThrowsError(try HTSPCommercials.recordingID(item, metadata: [wrong]))
        wrong = base; wrong["idStr"] = .string(String(repeating: "f", count: 32))
        XCTAssertThrowsError(try HTSPCommercials.recordingID(item, metadata: [wrong]))
        XCTAssertThrowsError(try HTSPCommercials.recordingID(item, metadata: [base, base]))
        let exact: [String: HTSPValue] = ["id": .integer(99), "idStr": .string(item.id.uppercased())]
        XCTAssertEqual(try HTSPCommercials.recordingID(item, metadata: [exact]), 99)
    }

    @MainActor func testPreferencesDefaultToManualAndPersistWithoutChangingConnectionCredentials() throws {
        let suite = "CommercialTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CommercialPreferences(defaults: defaults)
        let connection = Connection(address: "http://tvheadend.example:9981/root", username: "fixture", password: "fixture-password")
        XCTAssertFalse(preferences.automatic)
        XCTAssertEqual(try preferences.endpoint(for: connection), .init(host: "tvheadend.example", port: 9982))
        preferences.automatic = true; preferences.host = "192.0.2.1"; preferences.port = 29982
        let restored = CommercialPreferences(defaults: defaults)
        XCTAssertTrue(restored.automatic)
        XCTAssertEqual(try restored.endpoint(for: connection), .init(host: "192.0.2.1", port: 29982))
        preferences.host = "http://other.example"; XCTAssertThrowsError(try preferences.endpoint(for: connection))
        preferences.host = ""; preferences.port = 0; XCTAssertThrowsError(try preferences.endpoint(for: connection))
        XCTAssertNil(defaults.string(forKey: "password"))
    }

    @MainActor func testSelectionLoadsOnlyItsMarkersAndRejectsCancelledLateRepliesWithoutAutoplay() async {
        let first = SavedRecording(uuid: String(repeating: "a", count: 32), start: 10, filesize: 100, sched_status: "completed")
        var second = first; second = SavedRecording(uuid: String(repeating: "b", count: 32), start: 50, filesize: 100, sched_status: "completed")
        let stub = CommercialLibraryStub([first, second]), library = RecordingLibrary()
        library.configure(stub); library.setActive(true); await library.refresh()
        await stub.set(delay: true)
        library.select(first)
        let old = library.loadCommercials(force: true)
        await Task.yield()
        library.select(second)
        let current = library.loadCommercials(force: true)
        await current?.value; await old?.value
        XCTAssertEqual(library.selected?.id, second.id)
        XCTAssertEqual(library.commercialBreaks, [.init(start: 50, end: 70)])
        XCTAssertEqual(library.commercialFileDuration, 100)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertNil(library.commercialsError)
        let count = await stub.calls
        XCTAssertNil(library.loadCommercials())
        let unchanged = await stub.calls
        XCTAssertEqual(count, unchanged)
        library.select(nil)
        XCTAssertTrue(library.commercialBreaks.isEmpty)
        XCTAssertNil(library.commercialFileDuration)
        XCTAssertFalse(library.commercialsLoading)
        library.configure(nil)
    }

    func testFileClockUsesActualSingleFileTimesInsteadOfScheduledProgrammeDuration() {
        XCTAssertEqual(HTSPCommercials.fileDuration(["files": .list([
            .map(["start": .integer(100), "stop": .integer(160)])
        ])]), 60)
        XCTAssertNil(HTSPCommercials.fileDuration([:]))
        XCTAssertNil(HTSPCommercials.fileDuration(["files": .list([
            .map(["start": .integer(160), "stop": .integer(100)])
        ])]))
        XCTAssertNil(HTSPCommercials.fileDuration(["files": .list([
            .map(["start": .integer(100), "stop": .integer(160)]),
            .map(["start": .integer(200), "stop": .integer(260)])
        ])]))
    }

    @MainActor func testMarkerFailureIsSeparateFromPlaybackAndRetryClearsIt() async {
        let item = SavedRecording(uuid: String(repeating: "a", count: 32), start: 10, filesize: 100, sched_status: "completed")
        let stub = CommercialLibraryStub([item]), library = RecordingLibrary()
        library.configure(stub); library.setActive(true); await library.refresh()
        await stub.set(fail: true)
        library.select(item)
        await library.loadCommercials(force: true)?.value
        XCTAssertNotNil(library.commercialsError)
        XCTAssertNil(library.playbackError)
        XCTAssertFalse(library.playbackRequested)
        XCTAssertFalse(library.canSkipCommercial)
        await stub.set(fail: false)
        await library.loadCommercials(force: true)?.value
        XCTAssertNil(library.commercialsError)
        XCTAssertEqual(library.commercialBreaks, [.init(start: 10, end: 30)])
        library.setActive(false)
        XCTAssertTrue(library.commercialBreaks.isEmpty)
        library.configure(nil)
    }
}
