import XCTest
@testable import Tunerfenster

private actor LibraryStub: RecordingLibraryAPI {
    let values: [SavedRecording]
    let delayed: Bool
    init(_ values: [SavedRecording], delayed: Bool = false) { self.values = values; self.delayed = delayed }
    func savedRecordings() async throws -> [SavedRecording] {
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        return values
    }
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL {
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        return URL(string: "http://localhost/dvrfile/\(recording.id)?ticket=fixture")!
    }
}

final class RecordingLibraryTests: XCTestCase {
    let id = String(repeating: "a", count: 32)
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
    func client() -> API {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryURLProtocol.self]
        return API(connection: Connection(address: "http://localhost:9981/tvh", username: "fixture", password: "fixture"), configuration: configuration)
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
