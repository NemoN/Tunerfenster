import XCTest
@testable import Tunerfenster

final class ProgrammeTests: XCTestCase {
    func testNowNextBoundaryProgressAndUntrustedChannelFiltering() {
        let current = Programme(eventId: 1, channelUuid: "channel", start: 100, stop: 200, title: "Current")
        let next = Programme(eventId: 2, channelUuid: "channel", start: 200, stop: 300, title: "Next")
        let unrelated = Programme(eventId: 3, channelUuid: "other", start: 100, stop: 500, title: "Wrong channel")
        let invalid = Programme(eventId: 4, channelUuid: "channel", start: 400, stop: 300)
        let schedule = ProgrammeSchedule(events: [next, unrelated, invalid, current], channelID: "channel")
        XCTAssertEqual(schedule.events.count, 2)
        XCTAssertEqual(schedule.current(at: Date(timeIntervalSince1970: 150))?.id, 1)
        XCTAssertEqual(schedule.next(at: Date(timeIntervalSince1970: 150))?.id, 2)
        XCTAssertEqual(schedule.current(at: Date(timeIntervalSince1970: 200))?.id, 2)
        XCTAssertNil(schedule.current(at: Date(timeIntervalSince1970: 300)))
        XCTAssertNil(schedule.next(at: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(current.progress(at: Date(timeIntervalSince1970: 150)), 0.5)
        XCTAssertEqual(current.progress(at: Date(timeIntervalSince1970: 50)), 0)
        XCTAssertEqual(current.progress(at: Date(timeIntervalSince1970: 250)), 1)
    }

    func testEPGChannelMappingUsesServiceIdentityAndRejectsAmbiguousNames() {
        let servicePreview = Preview(id: 1, title: "ZDF HD", path: "stream/service/sat-service", sourceState: "")
        let channel = Channel(uuid: "zdf", name: "ZDF HD", services: ["sat-service", "cable-service"])
        XCTAssertEqual(ProgrammeSchedule.channel(for: servicePreview, channels: [channel])?.uuid, "zdf")
        XCTAssertNil(ProgrammeSchedule.channel(for: servicePreview, channels: [Channel(uuid: "wrong", name: "ZDF HD", services: ["other-service"])]))
        let ambiguous = Preview(id: 2, title: "Unknown", path: servicePreview.path, sourceState: "")
        XCTAssertNil(ProgrammeSchedule.channel(for: ambiguous, channels: [channel, Channel(uuid: "alias", name: "Alias", services: ["sat-service"])]))
        let direct = Preview(id: 3, title: "ZDF", path: "stream/channel/zdf", sourceState: "")
        XCTAssertEqual(ProgrammeSchedule.channel(for: direct, channels: [channel])?.uuid, "zdf")
        XCTAssertNil(ProgrammeSchedule.channel(for: servicePreview, channels: [Channel(uuid: "zdf", name: "ZDF HD", enabled: false, services: ["sat-service"])]))
    }

    func testDescriptionFallsBackToSummaryAndMissingDescriptionDecodes() throws {
        let event = try JSONDecoder().decode(Programme.self, from: Data(#"{"eventId":1,"channelUuid":"channel","start":100,"stop":200,"summary":"Summary only"}"#.utf8))
        XCTAssertEqual(event.details, "Summary only")
        let description = Programme(eventId: 2, channelUuid: "channel", start: 100, stop: 200, summary: "Summary", description: " Full description \n")
        XCTAssertEqual(description.details, "Full description")
    }

    @MainActor func testEnlargingUnmutesOnlyFocusedChannelAndCollapsingMutesEverything() {
        let monitor = Monitor()
        let a = Tuner(input: Input(uuid: "a", input: "Tuner A"), previews: [Preview(id: 1, title: "A", path: "stream/service/a", sourceState: "")], hasEPG: false, unresolvedTV: false)
        let b = Tuner(input: Input(uuid: "b", input: "Tuner B"), previews: [Preview(id: 2, title: "B", path: "stream/service/b", sourceState: "")], hasEPG: false, unresolvedTV: false)
        monitor.tuners = [a, b]; monitor.connected = true
        monitor.toggleAudio(b.id)
        monitor.focus(a.id)
        XCTAssertEqual(monitor.audioID, a.id)
        monitor.toggleAudio(a.id)
        monitor.updateFocusedAudio()
        XCTAssertNil(monitor.audioID, "An explicit mute in the focused view must survive polling")
        monitor.focus(b.id)
        XCTAssertEqual(monitor.audioID, b.id)
        monitor.focus(nil)
        XCTAssertNil(monitor.audioID)
        XCTAssertNil(monitor.focusedID)
        monitor.shutdown()
    }

    @MainActor func testFocusedChannelMutesWhenItStopsAndUnmutesWhenItReturns() {
        let monitor = Monitor()
        let input = Input(uuid: "a", input: "Tuner A")
        let active = Tuner(input: input, previews: [Preview(id: 1, title: "A", path: "stream/service/a", sourceState: "")], hasEPG: false, unresolvedTV: false)
        monitor.tuners = [active]; monitor.connected = true
        monitor.focus(input.id)
        XCTAssertEqual(monitor.audioID, input.id)
        monitor.tuners = [Tuner(input: input, previews: [], hasEPG: false, unresolvedTV: false)]
        monitor.updateFocusedAudio()
        XCTAssertNil(monitor.audioID)
        monitor.tuners = [active]
        monitor.updateFocusedAudio()
        XCTAssertEqual(monitor.audioID, input.id)
        monitor.shutdown()
    }
}
