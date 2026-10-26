import XCTest
@testable import Tunerfenster

final class TunerUsageTests: XCTestCase {
    func tuner(_ name: String, subscribers: Int) -> Tuner {
        Tuner(input: Input(uuid: name, input: name, stream: "Mux in Sat", subs: subscribers),
              previews: [], hasEPG: false, unresolvedTV: false)
    }

    func testUsageKindsUseServerMarkersAndKeepUnrecognisedUsesSeparate() {
        XCTAssertEqual(Subscription(id: 1, channel: "News", title: "HTTP").usageKind, .tv)
        XCTAssertEqual(Subscription(id: 2, channel: "News", title: "DVR: Evening news").usageKind, .recording)
        XCTAssertEqual(Subscription(id: 3, service: "Tuner/Sat/Mux/Raw PID Subscription", title: "epggrab").usageKind, .epg)
        XCTAssertEqual(Subscription(id: 4, title: "HTTP", client: "Tunerfenster/1.0").usageKind, .preview)
        XCTAssertEqual(Subscription(id: 5, title: "DVR: epggrab documentary").usageKind, .recording)
        XCTAssertEqual(Subscription(id: 6, service: "Tuner/Sat/Mux/Raw PID Subscription", title: "scan").usageKind, .other)
        XCTAssertEqual(Subscription(id: 7, title: "Unknown internal task").usageKind, .other)
        XCTAssertEqual(Subscription(id: 8).usageKind, .other)
    }

    func testOverviewGroupsConcurrentUsesByFullInputNameWithoutPrefixCollisions() {
        let a = tuner("Adapter DVB-S/S2 #1", subscribers: 4)
        let b = tuner("Adapter DVB-S/S2 #10", subscribers: 1)
        let longer = tuner(a.id + "/extra", subscribers: 1)
        let subscriptions = [
            Subscription(id: 4, channel: "News", service: a.id + "/Sat/Mux/News", title: "HTTP", client: previewClient),
            Subscription(id: 2, channel: "News", service: a.id + "/Sat/Mux/News", title: "DVR: Evening news"),
            Subscription(id: 1, channel: "News", service: a.id + "/Sat/Mux/News", title: "HTSP", client: "Kodi"),
            Subscription(id: 3, service: a.id + "/Sat/Mux/Raw PID Subscription", title: "epggrab"),
            Subscription(id: 5, channel: "Sport", service: b.id + "/Sat/Mux/Sport", title: "HTTP"),
            Subscription(id: 6, channel: "Film", service: longer.id + "/Sat/Mux/Film", title: "HTTP")
        ]
        let result = TunerUsage.overview(tuners: [a, b, longer], subscriptions: subscriptions)
        XCTAssertEqual(result.map(\.id), [a.id, b.id, longer.id])
        XCTAssertEqual(result[0].subscriptions.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(result[0].subscriptions.map(\.usageKind), [.tv, .recording, .epg, .preview])
        XCTAssertEqual(result[1].subscriptions.map(\.id), [5])
        XCTAssertEqual(result[2].subscriptions.map(\.id), [6])
        XCTAssertTrue(result.allSatisfy { $0.unassignedCount == 0 })
    }

    func testMissingSubscriptionDetailsDoNotHideAnOccupiedTunerOrInventAnAssignment() {
        let occupied = tuner("Busy", subscribers: 3)
        let idle = tuner("Idle", subscribers: 0)
        let subscriptions = [
            Subscription(id: 1, channel: "News", service: "Busy/Sat/Mux/News", title: "HTTP"),
            Subscription(id: 2, title: "DVR: Not assigned yet"),
            Subscription(id: 3, service: "Other tuner/Sat/Mux/News", title: "HTTP"),
            Subscription(id: 4, service: "Idle/Sat/Mux/News", title: "HTTP")
        ]
        let result = TunerUsage.overview(tuners: [occupied, idle], subscriptions: subscriptions)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, occupied.id)
        XCTAssertEqual(result[0].subscriptions.map(\.id), [1])
        XCTAssertEqual(result[0].unassignedCount, 2)
        XCTAssertTrue(TunerUsage.overview(tuners: [], subscriptions: subscriptions).isEmpty)
    }

    func testRecordingMarkersUseActiveDVRSubscriptionsOnTheCorrectInput() {
        let a = tuner("Adapter DVB-S/S2 #1", subscribers: 2)
        let b = tuner("Adapter DVB-S/S2 #10", subscribers: 2)
        let idle = tuner("Idle", subscribers: 0)
        let subscriptions = [
            Subscription(id: 1, channel: "News", service: a.id + "/Sat/Mux/News", title: "HTTP"),
            Subscription(id: 2, service: a.id + "/Sat/Mux/Raw PID Subscription", title: "epggrab"),
            Subscription(id: 3, channel: "Film", service: b.id + "/Sat/Mux/Film", title: "DVR: Film"),
            Subscription(id: 4, channel: "News", service: b.id + "/Sat/Mux/News", title: "DVR: News"),
            Subscription(id: 5, title: "DVR: Not assigned yet"),
            Subscription(id: 6, service: idle.id + "/Sat/Mux/Film", title: "DVR: Stale status"),
            Subscription(id: 7, service: a.id + "/Sat/Mux/News", title: "HTTP", client: previewClient)
        ]
        XCTAssertEqual(TunerUsage.recordingInputIDs(tuners: [a, b, idle], subscriptions: subscriptions), [b.id])
        XCTAssertTrue(TunerUsage.recordingInputIDs(tuners: [a, b, idle], subscriptions: []).isEmpty,
                      "The indicator must disappear after the recorder subscription ends")
    }

    func testRecordingMarkerFollowsSwappedHeaderRatherThanOriginalTile() {
        let six = tuner("6", subscribers: 0)
        let eight = tuner("8", subscribers: 2)
        let subscriptions = [Subscription(id: 1, channel: "RTL", service: "8/Sat/Mux/RTL", title: "DVR: Programme")]
        let recordingInputs = TunerUsage.recordingInputIDs(tuners: [six, eight], subscriptions: subscriptions)
        let presentation = TunerHeaders.presentation(tuners: [six, eight], manualSources: [six.id: [eight.id]],
                                                       manualPaths: [six.id: "RTL"], activeIDs: [six.id, eight.id])
        XCTAssertTrue(recordingInputs.contains(presentation.headers[six.id]!))
        XCTAssertFalse(recordingInputs.contains(presentation.headers[eight.id]!))
    }

    func testUsageNamesAndDetailsPreferChannelAndRecorderProgrammeWithoutLeakingServicePaths() {
        let input = tuner("Adapter DVB-S/S2 #1", subscribers: 1).input
        let recording = Subscription(id: 1, channel: "News", service: input.id + "/Sat/Mux/Raw", title: "DVR: Evening news")
        XCTAssertEqual(recording.usageName(for: input), "News")
        XCTAssertEqual(recording.usageDetail, "Evening news")
        let epg = Subscription(id: 2, service: input.id + "/Sat/Mux/Raw PID Subscription", title: "epggrab")
        XCTAssertEqual(epg.usageName(for: input), "Mux in Sat")
        let tv = Subscription(id: 3, service: input.id + "/Sat/Mux/News", title: "HTTP", client: "Kodi")
        XCTAssertEqual(tv.usageName(for: input), "News")
        XCTAssertEqual(tv.usageDetail, "Kodi")
        XCTAssertNil(Subscription(id: 4, client: previewClient).usageDetail)
    }
}
