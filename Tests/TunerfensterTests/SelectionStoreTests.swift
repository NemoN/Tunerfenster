import XCTest
@testable import Tunerfenster

final class SelectionStoreTests: XCTestCase {
    func testPipedConnectionImportValidatesAddressAndAuthentication() throws {
        let connection = Connection(address: "http://localhost:9981", username: "test", password: "test-password")
        XCTAssertEqual(try Connection.fromImportData(JSONEncoder().encode(connection)), connection)
        let invalid = Connection(address: "http://user:secret@localhost:9981", username: "test", password: "test-password")
        XCTAssertThrowsError(try Connection.fromImportData(JSONEncoder().encode(invalid)))
        XCTAssertThrowsError(try Connection.fromImportData(Data("invalid".utf8)))
    }

    func isolatedDefaults() throws -> (String, UserDefaults) {
        let suite = "TunerfensterSelections.\(UUID().uuidString)"
        return (suite, try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    func testScopeNormalisesAddressButSeparatesServerAndAccountWithoutPassword() throws {
        let a = Connection(address: "http://TVH.local:80/", username: "user", password: "secret")
        let b = Connection(address: "http://tvh.local", username: "user", password: "changed")
        XCTAssertEqual(SelectionStore.scope(for: a), SelectionStore.scope(for: b))
        XCTAssertFalse(try XCTUnwrap(SelectionStore.scope(for: a)).contains("secret"))
        XCTAssertNotEqual(SelectionStore.scope(for: a), SelectionStore.scope(for: Connection(address: a.address, username: "other", password: "secret")))
        XCTAssertNotEqual(SelectionStore.scope(for: a), SelectionStore.scope(for: Connection(address: "http://tvh.local/proxy", username: "user", password: "secret")))
    }

    func testSelectionsSurviveNewStoreAndAutomaticModeRemovesOnlyChosenTile() throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        store.save(["Tuner A": "service-a", "Tuner B": "service-b"], scope: "server-a")
        store.save(["Tuner A": "other-service"], scope: "server-b")
        let reopened = SelectionStore(defaults: defaults)
        XCTAssertEqual(reopened.load(scope: "server-a"), ["Tuner A": "service-a", "Tuner B": "service-b"])
        reopened.save(["Tuner B": "service-b"], scope: "server-a")
        XCTAssertNil(store.load(scope: "server-a")["Tuner A"])
        XCTAssertEqual(store.load(scope: "server-a")["Tuner B"], "service-b")
        XCTAssertEqual(store.load(scope: "server-b")["Tuner A"], "other-service")
    }

    @MainActor func testQuitPreservesPendingSelectionsWhenServerOrTunerIsUnavailable() throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let scope = try XCTUnwrap(SelectionStore.scope(for: connection))
        store.save(["Tuner A": "service-a", "Temporarily absent": "service-b"], scope: scope)
        let monitor = Monitor(selectionStore: store)
        monitor.loadSelections(for: connection)
        monitor.resolveSelections()
        monitor.shutdown()
        XCTAssertEqual(store.load(scope: scope).count, 2)
        let restarted = Monitor(selectionStore: store)
        restarted.loadSelections(for: connection)
        let tuner = Tuner(input: Input(uuid: "new-instance", input: "Tuner A"), previews: [Preview(id: 1, title: "Unrelated automatic channel", path: "stream/service/other", sourceState: "")], hasEPG: false, unresolvedTV: false)
        restarted.tuners = [tuner]
        XCTAssertNil(restarted.preview(for: tuner), "A missing saved service must not silently change to another channel")
        let choice = StreamChoice(service: Service(uuid: "service-a", svcname: "Saved"), name: "Saved", mapped: true, multiplex: nil)
        restarted.choose(choice, for: tuner)
        restarted.shutdown()
        XCTAssertEqual(store.load(scope: scope)["Tuner A"], "service-a")
        restarted.choose(nil, for: tuner)
        XCTAssertNil(store.load(scope: scope)["Tuner A"])
        XCTAssertEqual(store.load(scope: scope)["Temporarily absent"], "service-b")
        XCTAssertNotNil(restarted.preview(for: tuner))
        restarted.shutdown()
    }

    func testInvalidPreferencesRecoverWithoutStartingUnknownStreams() throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: SelectionStore.key)
        XCTAssertTrue(SelectionStore(defaults: defaults).load(scope: "server").isEmpty)
    }

    @MainActor func testFollowAllClearsActiveAndUnavailableAssignmentsOnlyForCurrentServerAndSurvivesRestart() throws {
        let (suite, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let scope = try XCTUnwrap(SelectionStore.scope(for: connection))
        store.save(["A": "manual-a", "Absent": "manual-absent"], scope: scope)
        store.save(["B": "other-service"], scope: "other-server")
        let monitor = Monitor(selectionStore: store)
        monitor.loadSelections(for: connection)
        let automatic = Preview(id: 1, title: "Following", path: "stream/service/automatic", sourceState: "")
        let tuner = Tuner(input: Input(uuid: "a", input: "A"), previews: [automatic], hasEPG: false, unresolvedTV: false)
        monitor.tuners = [tuner]; monitor.connected = true
        monitor.choose(StreamChoice(service: Service(uuid: "manual-a"), name: "Manual", mapped: true, multiplex: nil), for: tuner)
        monitor.setViewingMode(.tv)
        monitor.followAll()
        XCTAssertTrue(monitor.savedManual.isEmpty)
        XCTAssertTrue(monitor.manual.isEmpty)
        XCTAssertEqual(monitor.preview(for: tuner)?.path, automatic.path)
        XCTAssertEqual(monitor.viewingMode, .tv)
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [tuner.id])
        XCTAssertTrue(store.load(scope: scope).isEmpty)
        XCTAssertEqual(store.load(scope: "other-server"), ["B": "other-service"])
        monitor.shutdown()
        let restarted = Monitor(selectionStore: SelectionStore(defaults: defaults))
        restarted.loadSelections(for: connection)
        XCTAssertTrue(restarted.savedManual.isEmpty)
        XCTAssertEqual(restarted.viewingMode, .tv, "Follow all preserves the saved viewing mode")
        XCTAssertNil(restarted.audioID)
        restarted.shutdown()
    }
}
