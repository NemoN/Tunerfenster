import XCTest
@testable import Tunerfenster

private actor RecordingStub: RecordingAPI {
    let profiles: [RecordingProfile]
    let event: Programme?
    var requests = [(Int, String)]()
    var entry: RecordingEntry?
    var created = [String: RecordingEntry]()
    var stops = [String]()
    let keepRunning: Bool
    let refuseStop: Bool
    let refuseActiveCheck: Bool
    init(profiles: [RecordingProfile], event: Programme?, entry: RecordingEntry? = nil,
         keepRunning: Bool = false, refuseStop: Bool = false, refuseActiveCheck: Bool = false) {
        self.profiles = profiles; self.event = event; self.entry = entry
        self.keepRunning = keepRunning; self.refuseStop = refuseStop
        self.refuseActiveCheck = refuseActiveCheck
    }
    func recordingProfiles() async throws -> [RecordingProfile] { profiles }
    func seedRecording(_ entry: RecordingEntry) { created[entry.uuid] = entry }
    func recordingEvent(_ event: Programme, language: AppLanguage) async throws -> Programme? {
        try await Task.sleep(for: .milliseconds(20))
        return self.event
    }
    func activeRecordings(for event: Programme) async throws -> [RecordingEntry] {
        if refuseActiveCheck { throw AppError.message("missingPermissions") }
        return (Array(created.values) + [entry].compactMap { $0 }).filter { !$0.isFinished && $0.refersTo(event) }
    }
    func recordProgramme(eventID: Int, profileID: String) async throws -> String {
        requests.append((eventID, profileID))
        let uuid = requests.count == 1 ? "recording-id" : "recording-id-\(requests.count)"
        created[uuid] = RecordingEntry(uuid: uuid, channel: event?.channelUuid, broadcast: eventID, sched_status: "recording")
        return uuid
    }
    func recordingStatus(uuid: String) async throws -> RecordingEntry? {
        try await Task.sleep(for: .milliseconds(20))
        return created[uuid] ?? entry
    }
    func stopRecording(uuid: String) async throws {
        stops.append(uuid)
        if refuseStop { throw AppError.message("missingPermissions") }
        if let entry, entry.uuid == uuid, !keepRunning {
            self.entry = RecordingEntry(uuid: entry.uuid, channel: entry.channel, broadcast: entry.broadcast, sched_status: "completed")
        }
        if let entry = created[uuid], !keepRunning {
            created[uuid] = RecordingEntry(uuid: entry.uuid, channel: entry.channel, broadcast: entry.broadcast, sched_status: "completed")
        }
    }
}

final class RecordingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 150)
    private var event: Programme { Programme(eventId: 42, channelUuid: "channel", start: 100, stop: 200, title: "Current") }
    private var active: Programme {
        var result = event
        result.dvrUuid = "existing"
        result.dvrState = "recording"
        return result
    }

    @MainActor func testGracefulStopTargetsOneUUIDAndPreventsDoubleClick() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [], event: active,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "recording"))
        recorder.configure(stub)
        XCTAssertTrue(recorder.canStop(active), "Stopping must remain possible if a recording profile was disabled")
        async let first: Void = recorder.stop(active)
        await recorder.stop(active)
        await first
        let stops = await stub.stops
        XCTAssertEqual(stops, ["existing"])
        XCTAssertTrue(recorder.stopped.contains("existing"))
        XCTAssertFalse(recorder.isRecording(active))
        XCTAssertFalse(recorder.canRecord(active), "Starting again still requires an available recording profile")
        XCTAssertNil(recorder.errors[Recorder.key(active)])
    }

    @MainActor func testStoppedProgrammeCanRestartRepeatedlyAndStopTheNewUUIDWithStaleEPG() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: active,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "recording"))
        recorder.configure(stub)
        await recorder.refreshAvailability()
        await recorder.stop(active)
        XCTAssertTrue(recorder.canRestart(active))
        XCTAssertTrue(recorder.canRecord(active))
        for uuid in ["recording-id", "recording-id-2"] {
            async let first: Void = recorder.record(active)
            await recorder.record(active)
            await first
            XCTAssertEqual(recorder.recording(for: active).dvrUuid, uuid)
            XCTAssertTrue(recorder.isRecording(active))
            XCTAssertFalse(recorder.canRecord(active))
            XCTAssertFalse(recorder.canRestart(active))
            await recorder.stop(active)
            XCTAssertFalse(recorder.isRecording(active))
            XCTAssertTrue(recorder.canRecord(active))
        }
        let stops = await stub.stops
        let requests = await stub.requests
        let previous = await stub.entry
        let created = await stub.created
        XCTAssertEqual(stops, ["existing", "recording-id", "recording-id-2"])
        XCTAssertEqual(requests.count, 2, "Double clicks must not create extra files")
        XCTAssertTrue(previous?.isFinished == true, "The original entry must remain intact")
        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(created.values.allSatisfy(\.isFinished))
        XCTAssertNil(recorder.errors[Recorder.key(active)])
    }

    @MainActor func testFinishedRecordingCanRestartAfterAppRestartButOnlyDuringItsProgramme() async {
        var completed = active
        completed.dvrState = "completed"
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: completed,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "completed"))
        recorder.configure(stub)
        await recorder.refreshAvailability()
        XCTAssertTrue(recorder.stopped.isEmpty, "No in-memory stop history is required")
        XCTAssertTrue(recorder.canRecord(completed))
        await recorder.record(completed)
        XCTAssertTrue(recorder.isRecording(completed))
        XCTAssertEqual(recorder.recording(for: completed).dvrUuid, "recording-id")

        let ended = Recorder(now: { Date(timeIntervalSince1970: 200) })
        ended.configure(stub)
        await ended.refreshAvailability()
        XCTAssertFalse(ended.canRestart(completed))
        XCTAssertFalse(ended.canRecord(completed))
    }

    @MainActor func testAnotherClientsActiveRecordingBlocksRestartDespiteStaleCompletedEPG() async {
        var completed = active
        completed.dvrState = "completed"
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: completed,
                                 entry: .init(uuid: "other-client", channel: "channel", broadcast: 42, sched_status: "recording"))
        recorder.configure(stub)
        await recorder.refreshAvailability()
        await recorder.record(completed)
        let requests = await stub.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(recorder.isRecording(completed))
        XCTAssertEqual(recorder.recording(for: completed).dvrUuid, "other-client")
        XCTAssertFalse(recorder.canRecord(completed))
        await recorder.stop(completed)
        let stops = await stub.stops
        XCTAssertEqual(stops, ["other-client"])
    }

    @MainActor func testRestartRequiresSuccessfulDuplicateCheckAndConfirmedFinishedState() async {
        var completed = active
        completed.dvrState = "completed"
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: completed, refuseActiveCheck: true)
        recorder.configure(stub)
        await recorder.refreshAvailability()
        await recorder.record(completed)
        let requests = await stub.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(recorder.errors[Recorder.key(completed)])
        XCTAssertTrue(recorder.canRecord(completed), "A failed check can be retried")

        let unconfirmed = RecordingStub(profiles: [.init(uuid: "default")], event: active,
                                       entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "scheduled"))
        recorder.configure(unconfirmed)
        await recorder.refreshAvailability()
        await recorder.stop(active)
        XCTAssertTrue(recorder.stopped.isEmpty)
        XCTAssertFalse(recorder.canRecord(active))
        XCTAssertNotNil(recorder.errors[Recorder.key(active)])
    }

    @MainActor func testStatusRefreshRecoversCompletedStateAndDiscardsOldConnectionResults() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: active,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "completed"))
        recorder.configure(stub)
        await recorder.refreshAvailability()
        XCTAssertFalse(recorder.canRecord(active))
        await recorder.refreshRecording(active)
        XCTAssertTrue(recorder.canRecord(active))
        XCTAssertFalse(recorder.isRecording(active))
        await recorder.record(active)
        XCTAssertEqual(recorder.recording(for: active).dvrUuid, "recording-id")
        XCTAssertTrue(recorder.isRecording(active), "Direct DVR state must win over stale EPG state")
        let task = Task { await recorder.refreshRecording(active) }
        await Task.yield()
        recorder.configure(nil)
        await task.value
        XCTAssertTrue(recorder.entries.isEmpty)
    }

    @MainActor func testStatusRefreshFindsRestartedRecordingAfterRelaunchWithStaleEPG() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: active,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "completed"))
        await stub.seedRecording(.init(uuid: "restarted", channel: "channel", broadcast: 42, sched_status: "recording"))
        recorder.configure(stub)
        await recorder.refreshAvailability()
        await recorder.refreshRecording(active)
        XCTAssertTrue(recorder.isRecording(active))
        XCTAssertFalse(recorder.canRecord(active))
        XCTAssertEqual(recorder.recording(for: active).dvrUuid, "restarted")
        await recorder.stop(active)
        let stops = await stub.stops
        XCTAssertEqual(stops, ["restarted"])
        XCTAssertTrue(recorder.canRecord(active))
    }

    @MainActor func testStaleOrUnrelatedUUIDCannotStopAnotherRecording() async {
        let recorder = Recorder(now: { self.now })
        for entry in [RecordingEntry(uuid: "different", channel: "channel", broadcast: 42, sched_status: "recording"),
                      RecordingEntry(uuid: "existing", channel: "other-channel", broadcast: 42, sched_status: "recording"),
                      RecordingEntry(uuid: "existing", channel: "channel", broadcast: 43, sched_status: "recording")] {
            let stub = RecordingStub(profiles: [], event: active, entry: entry)
            recorder.configure(stub)
            await recorder.stop(active)
            let stops = await stub.stops
            XCTAssertTrue(stops.isEmpty)
            XCTAssertTrue(recorder.stopped.isEmpty)
            XCTAssertNotNil(recorder.errors[Recorder.key(active)])
        }
    }

    @MainActor func testAlreadyFinishedAndFailedStopsReportServerState() async {
        let recorder = Recorder(now: { self.now })
        let finished = RecordingStub(profiles: [], event: active,
                                     entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "completed"))
        recorder.configure(finished)
        await recorder.stop(active)
        let stops = await finished.stops
        XCTAssertTrue(stops.isEmpty)
        XCTAssertTrue(recorder.stopped.contains("existing"))
        for refuse in [false, true] {
            let rejected = RecordingStub(profiles: [], event: active,
                                         entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "recording"),
                                         keepRunning: true, refuseStop: refuse)
            recorder.configure(rejected)
            await recorder.stop(active)
            XCTAssertTrue(recorder.isRecording(active))
            XCTAssertFalse(recorder.stopped.contains("existing"))
            XCTAssertTrue(recorder.pending.isEmpty)
            XCTAssertNotNil(recorder.errors[Recorder.key(active)])
        }
    }

    @MainActor func testConnectionChangeWhileStoppingDoesNotMutateOldServer() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [], event: active,
                                 entry: .init(uuid: "existing", channel: "channel", broadcast: 42, sched_status: "recording"))
        recorder.configure(stub)
        let task = Task { await recorder.stop(active) }
        for _ in 0..<100 where recorder.pending.isEmpty { await Task.yield() }
        XCTAssertFalse(recorder.pending.isEmpty)
        recorder.configure(nil)
        await task.value
        let stops = await stub.stops
        XCTAssertTrue(stops.isEmpty)
        XCTAssertTrue(recorder.stopped.isEmpty)
        XCTAssertTrue(recorder.pending.isEmpty)
    }

    @MainActor func testDefaultProfileAndDoubleClickCreateOneRecording() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "other", name: "Other"), .init(uuid: "default")], event: event)
        recorder.configure(stub)
        await recorder.refreshAvailability()
        async let first: Void = recorder.record(event)
        await recorder.record(event)
        await first
        let requests = await stub.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, 42)
        XCTAssertEqual(requests.first?.1, "default")
        XCTAssertTrue(recorder.submitted.contains(Recorder.key(event)))
        XCTAssertFalse(recorder.canRecord(event))
    }

    @MainActor func testDeletedRecordingIsNotRetainedAsCurrentProgrammeHistory() async {
        let recorder = Recorder(now: { self.now })
        let stub = RecordingStub(profiles: [.init(uuid: "default")], event: event)
        recorder.configure(stub)
        await recorder.refreshAvailability()
        await recorder.record(event)
        await recorder.stop(event)
        XCTAssertTrue(recorder.canRestart(event))
        recorder.forgetRecording(uuid: "recording-id")
        XCTAssertTrue(recorder.canRecord(event))
        XCTAssertFalse(recorder.canRestart(event))
        XCTAssertFalse(recorder.recording(for: event).hasRecording)
        XCTAssertTrue(recorder.submitted.isEmpty)
    }

    @MainActor func testUnconfiguredProfilesAndEndedEventsDoNotRecord() async {
        let recorder = Recorder(now: { self.now })
        let unavailable = RecordingStub(profiles: [.init(uuid: "disabled", enabled: false), .init(uuid: "empty", storage: " ")], event: event)
        recorder.configure(unavailable)
        await recorder.refreshAvailability()
        XCTAssertNil(recorder.profile)
        XCTAssertNotNil(recorder.availabilityError)
        await recorder.record(event)
        let requests = await unavailable.requests
        XCTAssertTrue(requests.isEmpty)

        for fresh in [nil, Programme(eventId: 42, channelUuid: "channel", start: 50, stop: 140),
                      Programme(eventId: 43, channelUuid: "channel", start: 100, stop: 200),
                      Programme(eventId: 42, channelUuid: "other", start: 100, stop: 200)] as [Programme?] {
            let stub = RecordingStub(profiles: [.init(uuid: "default")], event: fresh)
            recorder.configure(stub)
            await recorder.refreshAvailability()
            await recorder.record(event)
            let attempts = await stub.requests
            XCTAssertTrue(attempts.isEmpty)
            XCTAssertNotNil(recorder.errors[Recorder.key(event)])
        }
    }

    @MainActor func testFreshEPGRecordingPreventsDuplicateAndConnectionChangeDiscardsResults() async {
        let recorder = Recorder(now: { self.now })
        var scheduled = event
        scheduled.dvrUuid = "existing"
        scheduled.dvrState = "scheduled"
        let existing = RecordingStub(profiles: [.init(uuid: "default")], event: scheduled)
        recorder.configure(existing)
        await recorder.refreshAvailability()
        await recorder.record(event)
        let requests = await existing.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(recorder.submitted.contains(Recorder.key(event)))

        let changed = RecordingStub(profiles: [.init(uuid: "default")], event: event)
        recorder.configure(changed)
        await recorder.refreshAvailability()
        let task = Task { await recorder.record(event) }
        for _ in 0..<100 where recorder.pending.isEmpty { await Task.yield() }
        XCTAssertFalse(recorder.pending.isEmpty, "Change the connection while EPG validation is in flight")
        recorder.configure(nil)
        await task.value
        let attempts = await changed.requests
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(recorder.pending.isEmpty)
        XCTAssertTrue(recorder.submitted.isEmpty)
    }

    func testEPGRecordingStatusAndCreationResponse() throws {
        let current = try JSONDecoder().decode(Programme.self, from: Data(#"{"eventId":42,"channelUuid":"channel","start":100,"stop":200,"dvrUuid":"existing","dvrState":"recording"}"#.utf8))
        XCTAssertTrue(current.hasRecording)
        XCTAssertTrue(current.recordingIsActive)
        var failed = current
        failed.dvrState = "recordingError"
        XCTAssertTrue(failed.recordingHasError)
        XCTAssertFalse(failed.recordingIsActive)
        XCTAssertFalse(current.isCurrent(at: Date(timeIntervalSince1970: 200)))
        for json in [#"{}"#, #"{"uuid":[]}"#, #"{"uuid":[""]}"#] {
            XCTAssertNil(try JSONDecoder().decode(CreatedRecording.self, from: Data(json.utf8)).identifier)
        }
    }
}

private final class RecordingURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class RecordingAPITests: XCTestCase {
    private func client() -> API {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return API(connection: Connection(address: "http://localhost:9981/tvh", username: "test", password: "secret"), configuration: configuration)
    }

    func testUpcomingProbeMatchesProgrammeAndChannelAndIgnoresFinishedFiles() async throws {
        let api = client()
        defer { api.close(); RecordingURLProtocol.respond = nil }
        RecordingURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/tvh/api/dvr/entry/grid_upcoming")
            return (200, Data(#"{"total":7,"entries":[{"uuid":"new-active","channel":"channel","broadcast":42,"sched_status":"recording"},{"uuid":"timer","channel":"channel","broadcast":42,"sched_status":"scheduled"},{"uuid":"old","channel":"channel","broadcast":42,"sched_status":"completed"},{"uuid":"wrong-channel","channel":"other","broadcast":42,"sched_status":"recording"},{"uuid":"other-event","channel":"channel","broadcast":43,"sched_status":"recording"},{"uuid":"known","channel":"channel","sched_status":"recording"},{"uuid":"unknown-event","channel":"channel","sched_status":"recording"}]}"#.utf8))
        }
        let event = Programme(eventId: 42, channelUuid: "channel", start: 100, stop: 200, dvrUuid: "known")
        let active = try await api.activeRecordings(for: event)
        XCTAssertEqual(Set(active.map(\.uuid)), ["new-active", "timer", "known"])
    }

    func testPOSTUsesEventIdentityAndFormBodyAndRequiresConfirmationUUID() async throws {
        let api = client()
        defer { api.close(); RecordingURLProtocol.respond = nil }
        var response = #"{"uuid":["recording-uuid"]}"#
        RecordingURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/tvh/api/dvr/entry/create_by_event")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.url?.password)
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
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(body.contains("event_id=42"))
            XCTAssertTrue(body.contains("config_uuid=profile%2Btest"))
            XCTAssertFalse(body.contains("secret"))
            return (200, Data(response.utf8))
        }
        let uuid = try await api.recordProgramme(eventID: 42, profileID: "profile+test")
        XCTAssertEqual(uuid, "recording-uuid")
        response = #"{}"#
        do { _ = try await api.recordProgramme(eventID: 42, profileID: "profile+test"); XCTFail("Empty success must not confirm a recording") }
        catch { XCTAssertTrue(error is AppError) }
    }

    func testRecorderPrivilegeProbeBlocksConfigurationForAnAdminWithoutRecorderRights() async {
        let api = client()
        defer { api.close(); RecordingURLProtocol.respond = nil }
        RecordingURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/tvh/api/dvr/entry/grid_upcoming")
            return (403, Data())
        }
        do { _ = try await api.recordingProfiles(); XCTFail("Recorder privilege is required") }
        catch { XCTAssertTrue(error is AppError) }
    }

    func testStopUsesGracefulEndpointAndReadsDVRStateByUUID() async throws {
        let api = client()
        defer { api.close(); RecordingURLProtocol.respond = nil }
        var stopCount = 0
        RecordingURLProtocol.respond = { request in
            let path = request.url!.path
            if request.httpMethod == "POST" {
                XCTAssertEqual(path, "/tvh/api/dvr/entry/stop")
                XCTAssertNil(request.url?.query)
                let stream = request.httpBodyStream
                stream?.open(); defer { stream?.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = stream?.read(&buffer, maxLength: buffer.count) ?? 0
                let body = request.httpBody ?? Data(buffer.prefix(max(0, count)))
                XCTAssertEqual(String(decoding: body, as: UTF8.self), "uuid=existing")
                stopCount += 1
                return (200, Data(#"{"success":1}"#.utf8))
            }
            XCTAssertEqual(path, "/tvh/api/idnode/load")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(query.contains(URLQueryItem(name: "uuid", value: "existing")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "grid", value: "1")))
            return (200, Data(#"{"entries":[{"uuid":"existing","channel":"channel","broadcast":42,"sched_status":"recording"}]}"#.utf8))
        }
        let entry = try await api.recordingStatus(uuid: "existing")
        XCTAssertTrue(entry?.isRunning == true)
        try await api.stopRecording(uuid: "existing")
        XCTAssertEqual(stopCount, 1)
    }
}
