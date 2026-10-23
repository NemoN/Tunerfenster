import XCTest
@testable import Tunerfenster

final class ViewingModeTests: XCTestCase {
    func tuner(_ name: String, active: Bool = true) -> Tuner {
        Tuner(input: Input(uuid: name, input: name),
              previews: active ? [Preview(id: name == "A" ? 1 : 2, title: name, path: "stream/service/\(name)", sourceState: "")] : [],
              hasEPG: false, unresolvedTV: false)
    }

    @MainActor func testMuteShortcutTargetsFocusedStreamAndSurvivesStatusRefresh() {
        let monitor = Monitor()
        let a = tuner("A"), b = tuner("B"), idle = tuner("Idle", active: false)
        monitor.tuners = [idle, a, b]; monitor.connected = true
        monitor.toggleMute()
        XCTAssertEqual(monitor.audioID, a.id, "In the mosaic M starts audio on the first active stream")
        monitor.toggleMute()
        XCTAssertNil(monitor.audioID)
        monitor.focus(b.id)
        XCTAssertEqual(monitor.audioID, b.id)
        monitor.toggleMute()
        monitor.updateFocusedAudio()
        XCTAssertNil(monitor.audioID, "Polling must preserve an explicit mute")
        monitor.toggleMute()
        XCTAssertEqual(monitor.audioID, b.id)
        monitor.focus(idle.id)
        monitor.toggleMute()
        XCTAssertNil(monitor.audioID, "An idle focused tuner must not unmute another stream")
        monitor.focus(b.id)
        monitor.togglePause()
        monitor.toggleMute()
        XCTAssertNil(monitor.audioID)
        monitor.connected = false
        monitor.paused = false
        monitor.toggleMute()
        XCTAssertNil(monitor.audioID)
        monitor.shutdown()
    }

    @MainActor func testTVPlaysOnlySelectedTunerAndMosaicRestoresAssignmentsMuted() throws {
        let suite = "TunerfensterModes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = Monitor(selectionStore: SelectionStore(defaults: defaults))
        let a = tuner("A"), b = tuner("B")
        monitor.tuners = [a, b]; monitor.connected = true
        for item in [a, b] {
            let choice = StreamChoice(service: Service(uuid: "manual-\(item.id)"), name: "Manual \(item.id)", mapped: true, multiplex: nil)
            monitor.choose(choice, for: item)
        }
        let assignments = monitor.savedManual
        monitor.focus(b.id)
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [a.id, b.id], "Enlarging the mosaic keeps the other previews running")
        monitor.setViewingMode(.tv)
        XCTAssertEqual(monitor.focusedID, b.id)
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [b.id])
        XCTAssertEqual(monitor.liveCount, 1)
        XCTAssertEqual(monitor.audioID, b.id)
        XCTAssertFalse(monitor.canSelectFocusedTuner)
        monitor.selectFocusedTuner(a.id)
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [b.id], "Manual TV playback cannot switch tuner slots")
        XCTAssertEqual(monitor.audioID, b.id)
        monitor.setViewingMode(.mosaic)
        XCTAssertNil(monitor.focusedID)
        XCTAssertNil(monitor.audioID)
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [a.id, b.id])
        XCTAssertEqual(monitor.liveCount, 2)
        XCTAssertEqual(monitor.savedManual, assignments)
        monitor.setViewingMode(.tv)
        XCTAssertEqual(monitor.focusedID, b.id, "Returning to TV remembers its last tuner")
        monitor.selectFocusedTuner("missing")
        XCTAssertEqual(monitor.focusedID, b.id)
        monitor.shutdown()
    }

    @MainActor func testTVSelectionHandlesLateOrDisappearingTunersAndPrefersAnActiveOne() {
        let monitor = Monitor()
        XCTAssertEqual(monitor.viewingMode, .mosaic)
        XCTAssertNil(monitor.audioID)
        monitor.setViewingMode(.tv)
        XCTAssertTrue(monitor.playbackTuners.isEmpty)
        let idle = tuner("Idle", active: false), active = tuner("B")
        monitor.connected = true
        monitor.tuners = [idle, active]
        monitor.ensureTVSelection()
        XCTAssertEqual(monitor.focusedID, active.id)
        XCTAssertEqual(monitor.audioID, active.id)
        monitor.tuners = [idle]
        monitor.ensureTVSelection()
        XCTAssertEqual(monitor.playbackTuners.map(\.id), [idle.id])
        XCTAssertNil(monitor.audioID)
        monitor.tuners = []
        monitor.ensureTVSelection()
        XCTAssertNil(monitor.focusedID)
        XCTAssertTrue(monitor.playbackTuners.isEmpty)
        monitor.shutdown()
    }

    @MainActor func testFocusedTunerSelectionIsAvailableOnlyWhileFollowingInTVAndZoom() {
        for mode in [ViewingMode.mosaic, .tv] {
            let monitor = Monitor()
            let a = tuner("A"), b = tuner("B")
            monitor.tuners = [a, b]; monitor.connected = true
            XCTAssertFalse(monitor.canSelectFocusedTuner)
            monitor.selectFocusedTuner(b.id)
            XCTAssertNil(monitor.focusedID, "The tuner selector must not open zoom from the mosaic")

            monitor.setViewingMode(mode)
            monitor.focus(a.id)
            XCTAssertTrue(monitor.canSelectFocusedTuner)
            monitor.selectFocusedTuner(b.id)
            XCTAssertEqual(monitor.focusedID, b.id)
            XCTAssertEqual(monitor.viewingMode, mode, "Selecting a tuner must preserve TV or mosaic zoom")
            XCTAssertEqual(monitor.audioID, b.id)
            XCTAssertEqual(monitor.playbackTuners.count, mode == .tv ? 1 : 2)

            let choice = StreamChoice(service: Service(uuid: "manual"), name: "Manual", mapped: true, multiplex: nil)
            monitor.choose(choice, for: b)
            XCTAssertFalse(monitor.canSelectFocusedTuner)
            monitor.selectFocusedTuner(a.id)
            XCTAssertEqual(monitor.focusedID, b.id)
            XCTAssertEqual(monitor.savedManual[b.id], choice.id, "A blocked tuner change must preserve the manual channel")

            monitor.choose(nil, for: b)
            XCTAssertTrue(monitor.canSelectFocusedTuner, "Returning to following restores the tuner selector")
            monitor.selectFocusedTuner("missing")
            XCTAssertEqual(monitor.focusedID, b.id)
            monitor.selectFocusedTuner(a.id)
            XCTAssertEqual(monitor.focusedID, a.id)
            monitor.shutdown()
        }
    }

    @MainActor func testUnresolvedSavedChannelKeepsTunerSelectionHiddenUntilFollowingIsRestored() throws {
        let suite = "TunerfensterFollowing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let scope = try XCTUnwrap(SelectionStore.scope(for: connection))
        store.save(["B": "unavailable-channel"], scope: scope)
        let monitor = Monitor(selectionStore: store, preferences: defaults)
        monitor.loadSelections(for: connection)
        monitor.tuners = [tuner("A"), tuner("B")]; monitor.connected = true
        monitor.focus("B")
        XCTAssertTrue(monitor.manual.isEmpty)
        XCTAssertFalse(monitor.canSelectFocusedTuner)
        monitor.selectFocusedTuner("A")
        XCTAssertEqual(monitor.focusedID, "B")
        monitor.followAll()
        XCTAssertTrue(monitor.canSelectFocusedTuner)
        monitor.selectFocusedTuner("A")
        XCTAssertEqual(monitor.focusedID, "A")
        monitor.shutdown()
    }

    @MainActor func testRestartRestoresTVTunerDespiteChangedMuxUUIDAndRemainsMutedAcrossPollingAndReconnect() throws {
        let suite = "TunerfensterRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let first = Monitor(selectionStore: store)
        first.loadSelections(for: connection)
        first.tuners = [tuner("A"), tuner("B")]; first.connected = true
        first.setViewingMode(.tv)
        first.selectFocusedTuner("B")
        first.shutdown()

        let restarted = Monitor(selectionStore: SelectionStore(defaults: defaults))
        restarted.loadSelections(for: connection)
        XCTAssertEqual(restarted.viewingMode, .tv)
        restarted.ensureTVSelection() // Tuner status has not arrived yet.
        let retuned = Tuner(input: Input(uuid: "different-mux-instance", input: "B"), previews: tuner("B").previews, hasEPG: false, unresolvedTV: false)
        restarted.tuners = [tuner("A"), retuned]; restarted.connected = true
        restarted.ensureTVSelection()
        XCTAssertEqual(restarted.focusedID, "B")
        XCTAssertEqual(restarted.playbackTuners.map(\.id), ["B"])
        restarted.updateFocusedAudio()
        XCTAssertNil(restarted.audioID)
        restarted.connected = false; restarted.updateFocusedAudio()
        restarted.connected = true; restarted.updateFocusedAudio()
        XCTAssertNil(restarted.audioID, "A restored TV session must not unmute itself during polling or reconnect")
        restarted.toggleAudio("B")
        XCTAssertEqual(restarted.audioID, "B")
        restarted.toggleAudio("B"); restarted.updateFocusedAudio()
        XCTAssertNil(restarted.audioID, "An explicit mute still survives polling")
        restarted.selectFocusedTuner("A")
        XCTAssertEqual(restarted.audioID, "A", "An explicit tuner change retains normal TV audio behavior")
        restarted.shutdown()
    }

    @MainActor func testMosaicRemembersTVTunerAndEarlyUserModeChangeSurvivesLoadingPreferences() throws {
        let suite = "TunerfensterRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let scope = try XCTUnwrap(SelectionStore.scope(for: connection))
        store.saveViewingState(ViewingState(mode: .tv, tunerID: "B"), scope: scope)
        let monitor = Monitor(selectionStore: store)
        monitor.loadSelections(for: connection)
        monitor.tuners = [tuner("A"), tuner("B")]; monitor.connected = true
        monitor.ensureTVSelection()
        monitor.setViewingMode(.mosaic)
        monitor.shutdown()
        XCTAssertEqual(store.loadViewingState(scope: scope), ViewingState(mode: .mosaic, tunerID: "B"))
        let restarted = Monitor(selectionStore: store)
        restarted.loadSelections(for: connection)
        XCTAssertEqual(restarted.viewingMode, .mosaic)
        XCTAssertNil(restarted.focusedID)
        restarted.tuners = [tuner("A"), tuner("B")]; restarted.connected = true
        restarted.setViewingMode(.tv)
        XCTAssertEqual(restarted.focusedID, "B")
        restarted.shutdown()

        let early = Monitor(selectionStore: store)
        early.setViewingMode(.mosaic) // User acts while connection/keychain loading is pending.
        early.loadSelections(for: connection)
        XCTAssertEqual(early.viewingMode, .mosaic)
        XCTAssertEqual(store.loadViewingState(scope: scope).tunerID, "B")
        early.shutdown()
    }

    @MainActor func testUnavailablePreferredTunerSurvivesFallbackAndReturnsWithoutUnexpectedAudio() throws {
        let suite = "TunerfensterRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let connection = Connection(address: "http://localhost:9981", username: "user", password: "secret")
        let scope = try XCTUnwrap(SelectionStore.scope(for: connection))
        store.saveViewingState(ViewingState(mode: .tv, tunerID: "B"), scope: scope)
        let monitor = Monitor(selectionStore: store)
        monitor.loadSelections(for: connection)
        monitor.connected = true; monitor.tuners = [tuner("A")]
        monitor.ensureTVSelection()
        XCTAssertEqual(monitor.focusedID, "A")
        XCTAssertEqual(store.loadViewingState(scope: scope).tunerID, "B")
        monitor.tuners = []; monitor.ensureTVSelection()
        XCTAssertEqual(store.loadViewingState(scope: scope).tunerID, "B")
        monitor.tuners = [tuner("A"), tuner("B")]; monitor.ensureTVSelection()
        XCTAssertEqual(monitor.focusedID, "B")
        XCTAssertNil(monitor.audioID)
        monitor.selectFocusedTuner("A")
        monitor.ensureTVSelection()
        XCTAssertEqual(monitor.focusedID, "A")
        XCTAssertEqual(store.loadViewingState(scope: scope).tunerID, "A")
        monitor.shutdown()
    }

    func testViewingPreferencesAreScopedAndCorruptDataFallsBackWithoutChangingChannels() throws {
        let suite = "TunerfensterRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        store.save(["A": "service"], scope: "server-a")
        store.saveViewingState(ViewingState(mode: .tv, tunerID: "B"), scope: "server-a")
        store.saveViewingState(ViewingState(mode: .mosaic, tunerID: "C"), scope: "server-b")
        let reopened = SelectionStore(defaults: defaults)
        XCTAssertEqual(reopened.loadViewingState(scope: "server-a"), ViewingState(mode: .tv, tunerID: "B"))
        XCTAssertEqual(reopened.loadViewingState(scope: "server-b"), ViewingState(mode: .mosaic, tunerID: "C"))
        XCTAssertEqual(reopened.loadViewingState(scope: "new-server"), ViewingState())
        defaults.set(Data(#"{"server-a":{"mode":"future-mode","tunerID":"B"}}"#.utf8), forKey: SelectionStore.viewingKey)
        XCTAssertEqual(store.loadViewingState(scope: "server-a"), ViewingState())
        XCTAssertEqual(store.load(scope: "server-a"), ["A": "service"])
    }
}
