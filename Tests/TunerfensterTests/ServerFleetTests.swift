import XCTest
@testable import Tunerfenster

final class ServerFleetTests: XCTestCase {
    func testServerProfilesNeverPersistPasswords() throws {
        let suite = "Tunerfenster.ServerFleetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ServerProfileStore(defaults: defaults)
        let connection = Connection(address: "http://tv.example:9981", username: "alice", password: "private-password", auth: "basic")
        let profile = ServerProfile(id: "a", name: "Wohnzimmer", connection: connection)
        store.save([profile])
        XCTAssertEqual(store.load(), [profile])
        let data = try XCTUnwrap(defaults.data(forKey: ServerProfileStore.key))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(connection.password))
    }

    @MainActor func testServersKeepDuplicateTunerNamesSeparateAndSwitchModesTogether() throws {
        let suite = "Tunerfenster.ServerFleetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = Connection(address: "http://server-a:9981", username: "a", password: "")
        let b = Connection(address: "http://server-b:9981", username: "b", password: "")
        let first = Monitor(), second = Monitor()
        first.connection = a; second.connection = b
        let tuner = Tuner(input: Input(uuid: "one", input: "DVB-S2 #1"), previews: [], hasEPG: false, unresolvedTV: false)
        first.tuners = [tuner]; second.tuners = [tuner]
        let nodes = [ServerFleet.Node(profile: .init(id: "a", connection: a), monitor: first),
                     ServerFleet.Node(profile: .init(id: "b", connection: b), monitor: second)]
        var selected: Connection?
        let fleet = ServerFleet(store: .init(defaults: defaults), nodes: nodes, activeID: "a", persistSelection: { selected = $0 })
        XCTAssertEqual(fleet.tiles.count, 2)
        XCTAssertEqual(Set(fleet.tiles.map(\.id)).count, 2)
        fleet.setMode(.tv)
        XCTAssertTrue(second.playbackTuners.isEmpty)
        fleet.setMode(.mosaic)
        XCTAssertEqual(second.playbackTuners.count, 1)
        fleet.focus(fleet.tiles[1])
        XCTAssertTrue(fleet.active === second)
        XCTAssertEqual(fleet.active.focusedID, tuner.id)
        XCTAssertEqual(selected, b)
        fleet.setMode(.recordings)
        XCTAssertTrue(first.playbackTuners.isEmpty)
        fleet.activate("a")
        XCTAssertEqual(fleet.active.viewingMode, .recordings)
        XCTAssertTrue(fleet.active === first)
        XCTAssertTrue(second.playbackTuners.isEmpty)
    }

    @MainActor func testCanonicalDuplicateIsRejectedBeforeSavingCredentials() throws {
        let suite = "Tunerfenster.ServerFleetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connection = Connection(address: "http://TV.example:9981/", username: "alice", password: "")
        let monitor = Monitor(); monitor.connection = connection
        let node = ServerFleet.Node(profile: .init(id: "a", connection: connection), monitor: monitor)
        let fleet = ServerFleet(store: .init(defaults: defaults), nodes: [node], activeID: "a", persistSelection: { _ in })
        let duplicate = Connection(address: "http://tv.example:9981", username: "alice", password: "different")
        XCTAssertThrowsError(try fleet.save(id: nil, name: "", connection: duplicate))
        XCTAssertEqual(fleet.nodes.count, 1)
    }

    @MainActor func testMuteShortcutTargetsTheAudibleServer() throws {
        let suite = "Tunerfenster.ServerFleetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = Connection(address: "http://server-a:9981", username: "", password: "")
        let b = Connection(address: "http://server-b:9981", username: "", password: "")
        let first = Monitor(), second = Monitor()
        first.connection = a; second.connection = b
        let preview = Preview(id: 1, title: "Test", path: "stream/test", sourceState: "Running")
        let tuner = Tuner(input: Input(uuid: "1", input: "Tuner #1"), previews: [preview], hasEPG: false, unresolvedTV: false)
        first.connected = true; second.connected = true
        first.tuners = [tuner]; second.tuners = [tuner]
        let nodes = [ServerFleet.Node(profile: .init(id: "a", connection: a), monitor: first),
                     ServerFleet.Node(profile: .init(id: "b", connection: b), monitor: second)]
        let fleet = ServerFleet(store: .init(defaults: defaults), nodes: nodes, activeID: "a", persistSelection: { _ in })
        second.toggleAudio(tuner.id)
        XCTAssertEqual(second.audioID, tuner.id)
        fleet.toggleMute()
        XCTAssertNil(second.audioID)
        XCTAssertNil(first.audioID)
        fleet.toggleMute()
        XCTAssertEqual(second.audioID, tuner.id)
        XCTAssertNil(first.audioID)
    }
}
