import XCTest
import SwiftUI
import AppKit
@testable import Tunerfenster

final class ChannelNavigationTests: XCTestCase {
    @MainActor final class ClickedTable: NSTableView {
        var clickedIndex = -1
        override var clickedRow: Int { clickedIndex }
    }
    let input = Input(uuid: "sat", input: "DVB-S2 #1")

    func choice(_ id: String, mapped: Bool = true, system: String = "DVB-S2") -> StreamChoice {
        StreamChoice(service: Service(uuid: id), name: id, mapped: mapped,
                     multiplex: Multiplex(uuid: id, delsys: system))
    }

    func testCurrentSelectionResolvesAutomaticServiceAndChannelFallbackWithoutNameGuessing() {
        let a = choice("a"), b = choice("b"), cable = choice("cable", system: "DVB-C")
        let channel = Channel(uuid: "ch", name: "Same name", services: ["cable", "b"])
        let preview = Preview(id: 3, title: "Same name", path: "stream/channel/ch", sourceState: "")
        XCTAssertEqual(StreamChoice.current(for: a.preview, input: input, choices: [a, b], channels: [])?.id, "a")
        XCTAssertEqual(StreamChoice.current(for: preview, input: input, choices: [a, cable, b], channels: [channel])?.id, "b")
        XCTAssertNil(StreamChoice.current(for: preview, input: input, choices: [a, b], channels: []))
        XCTAssertNil(StreamChoice.current(for: nil, input: input, choices: [a, b], channels: [channel]))
    }

    func testNavigationUsesListOrderWrapsAndSkipsUnmappedOrIncompatibleServices() {
        let choices = [choice("a"), choice("raw", mapped: false), choice("cable", system: "DVB-C"), choice("b"), choice("c")]
        func step(_ id: String?, _ direction: Int) -> String? {
            StreamChoice.adjacent(to: id, direction: direction, input: input, choices: choices)?.id
        }
        XCTAssertEqual(step("a", 1), "b")
        XCTAssertEqual(step("b", -1), "a")
        XCTAssertEqual(step("a", -1), "c")
        XCTAssertEqual(step("c", 1), "a")
        XCTAssertEqual(step(nil, 1), "a")
        XCTAssertEqual(step("unavailable", -1), "c")
        XCTAssertNil(step("a", 0))
        XCTAssertNil(StreamChoice.adjacent(to: nil, direction: 1, input: input, choices: []))
    }

    @MainActor func testDoubleClickActivatesClickedChannelRatherThanOldSelectionAndIgnoresEmptySpace() {
        let choices = [choice("a"), choice("b")]
        var activated = [String]()
        let list = ChannelChoiceList(items: choices, selectedID: .constant("a"), currentID: "a",
                                     revealID: "a", switchMHz: 11700, activate: { activated.append($0.id) })
        let coordinator = list.makeCoordinator()
        let table = ClickedTable()
        table.clickedIndex = 1
        coordinator.doubleClick(table)
        XCTAssertEqual(activated, ["b"])
        table.clickedIndex = -1
        coordinator.doubleClick(table)
        table.clickedIndex = 20
        coordinator.doubleClick(table)
        XCTAssertEqual(activated, ["b"], "Double-clicks outside channel rows must not switch the old selection")
    }

    @MainActor func testPollingIntervalDefaultsClampsPersistsAndDoesNotChangeViewingState() throws {
        let suite = "TunerfensterPolling.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = Monitor(selectionStore: SelectionStore(defaults: defaults), preferences: defaults)
        XCTAssertEqual(monitor.pollingSeconds, 3)
        monitor.focus("tuner")
        monitor.setPollingSeconds(7)
        XCTAssertEqual(monitor.pollingSeconds, 7)
        XCTAssertEqual(monitor.focusedID, "tuner")
        XCTAssertEqual(Monitor(preferences: defaults).pollingSeconds, 7)
        monitor.setPollingSeconds(0)
        XCTAssertEqual(monitor.pollingSeconds, 1)
        monitor.setPollingSeconds(1000)
        XCTAssertEqual(monitor.pollingSeconds, 60)
        XCTAssertEqual(PollingInterval.load(from: defaults), 60)
        monitor.shutdown()
    }
}
