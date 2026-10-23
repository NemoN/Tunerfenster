import XCTest
import AppKit
@testable import Tunerfenster

final class MonitorTests: XCTestCase {
    let input = Input(uuid: "tuner-1", input: "MaxLinear DVB-S/S2 #1")
    let service = Service(uuid: "service-1", network: "Sat", multiplex: "11362H", svcname: "ZDF HD")

    func subscription(id: Int = 1, client: String = "Kodi", title: String = "HTSP", name: String = "ZDF HD") -> Subscription {
        Subscription(id: id, channel: name, service: "\(input.input)/Sat/11362H/\(name)", title: title, client: client, state: "Running")
    }

    func testActiveStreamResolvesExactServiceEvenWhenAdapterContainsSlashes() {
        let result = Snapshot.tuners(inputs: [input], subscriptions: [subscription()], services: [service], channels: [])
        XCTAssertEqual(result.first?.previews.first?.path, "stream/service/service-1")
        XCTAssertEqual(result.first?.previews.first?.title, "ZDF HD")
    }

    func testOwnPreviewCannotKeepItselfAlive() {
        let result = Snapshot.tuners(inputs: [input], subscriptions: [subscription(client: previewClient)], services: [service], channels: [])
        XCTAssertTrue(result[0].previews.isEmpty)
        XCTAssertFalse(result[0].hasEPG)
        XCTAssertFalse(result[0].unresolvedTV)
        XCTAssertTrue(result[0].hasOwnPreview)
    }

    func testEPGDoesNotStartVideo() {
        var raw = subscription(title: "epggrab", name: "Raw PID Subscription")
        raw.channel = nil
        let result = Snapshot.tuners(inputs: [input], subscriptions: [raw], services: [service], channels: [])
        XCTAssertTrue(result[0].hasEPG)
        XCTAssertTrue(result[0].previews.isEmpty)
    }

    func testUnknownTVIsVisibleAndDoesNotChooseAnUnrelatedChannel() {
        let result = Snapshot.tuners(inputs: [input], subscriptions: [subscription(name: "Unknown")], services: [service], channels: [Channel(uuid: "other", name: "VOX")])
        XCTAssertTrue(result[0].unresolvedTV)
        XCTAssertTrue(result[0].previews.isEmpty)
    }

    func testChannelFallbackOnlyForUnambiguousNames() {
        let channels = [Channel(uuid: "channel-1", name: "ZDF HD")]
        let one = Snapshot.tuners(inputs: [input], subscriptions: [subscription()], services: [], channels: channels)
        XCTAssertEqual(one[0].previews.first?.path, "stream/channel/channel-1")
        let duplicate = Snapshot.tuners(inputs: [input], subscriptions: [subscription()], services: [], channels: channels + [Channel(uuid: "channel-2", name: "ZDF HD")])
        XCTAssertTrue(duplicate[0].previews.isEmpty)
    }

    func testMultipleSubscriptionsUseStableOrderAndKeepDifferentSourcesSeparate() {
        let other = Input(uuid: "other", input: "Another tuner")
        let result = Snapshot.tuners(inputs: [input, other], subscriptions: [subscription(id: 20), subscription(id: 5)], services: [service], channels: [])
        XCTAssertEqual(result.first { $0.id == input.id }?.previews.map(\.id), [5, 20])
        XCTAssertTrue(result.first { $0.id == other.id }!.previews.isEmpty)
    }

    func testRemovingExternalSubscriptionRemovesPreviewWithOwnSubscriptionRemaining() {
        let own = subscription(id: 9, client: previewClient)
        let before = Snapshot.tuners(inputs: [input], subscriptions: [subscription(), own], services: [service], channels: [])
        let after = Snapshot.tuners(inputs: [input], subscriptions: [own], services: [service], channels: [])
        XCTAssertEqual(before[0].previews.count, 1)
        XCTAssertTrue(after[0].previews.isEmpty)
    }

    func testTunerIdentitySurvivesMuxInstanceChanges() {
        let retuned = Input(uuid: "new-mux-instance", input: input.input, stream: "11954H in Sat")
        XCTAssertEqual(retuned.id, input.id)
    }

    @MainActor func testServerTunerUsageCountsInputsOnceRegardlessOfPreviewAssignmentsAndViewingMode() {
        let inputs = [
            Input(uuid: "tv", input: input.input, subs: 3),
            Input(uuid: "epg", input: "EPG tuner", subs: 1),
            Input(uuid: "own", input: "Preview tuner", subs: 1),
            Input(uuid: "unknown", input: "Unmapped tuner", subs: 2),
            Input(uuid: "idle", input: "Idle tuner", stream: "Last tuned mux", subs: 0, signal: 55000, bps: 1000),
            Input(uuid: "missing", input: "No subscription data")
        ]
        let subscriptions = [
            subscription(), subscription(id: 2), subscription(id: 3),
            Subscription(id: 4, service: "EPG tuner/Sat/Mux/Raw PID Subscription", title: "epggrab"),
            Subscription(id: 5, service: "Preview tuner/" + service.path, client: previewClient),
            Subscription(id: 6, service: "Unmapped tuner/Sat/Mux/Unknown", client: "Recorder")
        ]
        let monitor = Monitor()
        defer { monitor.shutdown() }
        monitor.connected = true
        monitor.tuners = Snapshot.tuners(inputs: inputs, subscriptions: subscriptions, services: [service], channels: [])
        XCTAssertEqual(monitor.busyTunerCount, 4, "Count physical inputs, including EPG, own previews and unmapped services")
        XCTAssertEqual(monitor.liveCount, 1)

        for tuner in monitor.tuners {
            monitor.choose(StreamChoice(service: service, name: "Manual", mapped: true, multiplex: nil), for: tuner)
        }
        XCTAssertEqual(monitor.liveCount, 6)
        XCTAssertEqual(monitor.busyTunerCount, 4, "A manual tile assignment must not count as another occupied tuner")
        monitor.setViewingMode(.tv)
        XCTAssertEqual(monitor.liveCount, 1)
        XCTAssertEqual(monitor.busyTunerCount, 4, "TV mode must retain the full server occupancy")

        let idleInputs = inputs.map { input in var idle = input; idle.subs = 0; return idle }
        monitor.tuners = Snapshot.tuners(inputs: idleInputs, subscriptions: [], services: [service], channels: [])
        XCTAssertEqual(monitor.busyTunerCount, 0, "Server updates must drive occupancy even while manual choices remain saved")
    }

    func testReceptionFrequencyUnitsAndBandBoundary() {
        let low = Multiplex(uuid: "sat", delsys: "DVB-S2", frequency: 11_493_750, polarisation: "H")
        XCTAssertEqual(low.frequencyMHz, 11493.75)
        XCTAssertEqual(low.band(switchMHz: 11700), "LOW")
        XCTAssertEqual(low.band(switchMHz: 11000), "HIGH")
        let high = Multiplex(uuid: "sat-high", delsys: "DVB-S", frequency: 11_700_000, polarisation: "V")
        XCTAssertEqual(high.band(switchMHz: 11700), "HIGH")
        let cable = Multiplex(uuid: "cable", delsys: "DVB-C/ANNEX_A", frequency: 546_000_000)
        XCTAssertEqual(cable.frequencyMHz, 546)
        XCTAssertNil(cable.band(switchMHz: 11700))
        XCTAssertFalse(cable.summary(switchMHz: 11700).contains("LOW"))
    }

    func testReceptionMatchesNetworkAsWellAsMuxNameAndRejectsAmbiguity() {
        let mux = Multiplex(uuid: "sat", network: "Sat", name: "11362H", delsys: "DVB-S2")
        let other = Multiplex(uuid: "other", network: "Other", name: "11362H", delsys: "DVB-S2")
        let tuned = Input(uuid: "instance", input: input.input, stream: "11362H in Sat")
        XCTAssertEqual(Snapshot.multiplex(for: tuned, multiplexes: [other, mux])?.id, "sat")
        XCTAssertNil(Snapshot.multiplex(for: tuned, multiplexes: [mux, mux]))
        XCTAssertNil(Snapshot.multiplex(for: input, multiplexes: [mux]))
    }

    func testDuplicateMuxNamesExposeOnlySharedReceptionValues() {
        let first = Multiplex(uuid: "s", network: "Sat", name: "10935.5V", delsys: "DVB-S", frequency: 10_935_500, polarisation: "V", symbolrate: 22_000_000, modulation: "QPSK")
        let second = Multiplex(uuid: "s2", network: "Sat", name: "10935.5V", delsys: "DVB-S2", frequency: 10_935_500, polarisation: "V", symbolrate: 22_000_000, modulation: "PSK/8")
        let tuned = Input(uuid: "instance", input: input.input, stream: "10935.5V in Sat")
        let shared = Snapshot.multiplex(for: tuned, multiplexes: [first, second])
        XCTAssertEqual(shared?.frequencyMHz, 10935.5)
        XCTAssertEqual(shared?.polarisation, "V")
        XCTAssertEqual(shared?.band(switchMHz: 11700), "LOW")
        XCTAssertNil(shared?.delsys)
        XCTAssertNil(shared?.modulation)
    }

    func testChannelChoicesUseConfiguredNamesAndKeepReceptionPathsSeparate() {
        let sat = Service(uuid: "sat", network: "Sat", multiplex: "11362H", svcname: "Raw ZDF", multiplex_uuid: "mux-sat")
        let cable = Service(uuid: "cable", network: "Cable", multiplex: "546MHz", svcname: "Raw ZDF", multiplex_uuid: "mux-cable")
        let disabled = Service(uuid: "disabled", svcname: "Hidden", enabled: false)
        let catalog = StreamChoice.catalog(services: [sat, cable, disabled], channels: [Channel(uuid: "ch", name: "ZDF HD", services: ["sat", "cable"])], multiplexes: [
            Multiplex(uuid: "mux-sat", delsys: "DVB-S2"), Multiplex(uuid: "mux-cable", delsys: "DVB-C/ANNEX_A")
        ])
        XCTAssertEqual(catalog.count, 2)
        XCTAssertTrue(catalog.allSatisfy { $0.mapped && $0.name == "ZDF HD" })
        XCTAssertEqual(catalog.filter { $0.matches(input: input) }.map(\.id), ["sat"])
        XCTAssertEqual(catalog.filter { $0.matches(input: Input(uuid: "c", input: "DVB-C tuner")) }.map(\.id), ["cable"])
        XCTAssertEqual(catalog.first { $0.id == "sat" }?.preview.path, "stream/service/sat")
    }

    func testActualPreviewSourceUsesFullInputNameAndOnlyOwnSubscriptions() {
        let other = Input(uuid: "other", input: "Other DVB-S/S2 #2")
        let own = subscription(client: previewClient)
        XCTAssertEqual(Snapshot.sources(for: service, inputs: [other, input], subscriptions: [own]).map(\.id), [input.id])
        XCTAssertTrue(Snapshot.sources(for: service, inputs: [input], subscriptions: [subscription()]).isEmpty)
        XCTAssertTrue(Snapshot.sources(for: Service(uuid: "unrelated", network: "Other", multiplex: "11362H", svcname: "ZDF HD"), inputs: [input], subscriptions: [own]).isEmpty)
    }

    @MainActor func testManualChoicePersistsWithoutExternalViewerAndReturnsToAutomatic() {
        let monitor = Monitor()
        let tuner = Tuner(input: input, previews: [], hasEPG: false, unresolvedTV: false)
        let other = Tuner(input: Input(uuid: "other", input: "Another tuner"), previews: [], hasEPG: false, unresolvedTV: false)
        let choice = StreamChoice(service: service, name: "ZDF HD", mapped: true, multiplex: nil)
        monitor.tuners = [tuner, other]
        XCTAssertNil(monitor.preview(for: tuner))
        monitor.choose(choice, for: tuner)
        XCTAssertEqual(monitor.preview(for: tuner)?.path, "stream/service/service-1")
        XCTAssertNil(monitor.preview(for: other))
        XCTAssertEqual(monitor.liveCount, 1)
        // The manual selection survives a new status instance for this input.
        let retuned = Tuner(input: Input(uuid: "new-instance", input: input.input), previews: [], hasEPG: true, unresolvedTV: false)
        XCTAssertEqual(monitor.preview(for: retuned)?.title, "ZDF HD")
        monitor.choose(nil, for: retuned)
        XCTAssertNil(monitor.preview(for: tuner))
        XCTAssertEqual(monitor.liveCount, 0)
        monitor.shutdown()
    }

    func testGridFitsAllTunersWithoutScrollingAcrossWindowSizes() {
        for count in [1, 2, 4, 8, 14, 16, 32] {
            for (width, height) in [(672.0, 360.0), (1000.0, 600.0), (1920.0, 980.0), (3840.0, 2000.0)] {
                for preferred in [0, 1, 4, 6] {
                    let fit = GridFit.calculate(count: count, width: width, height: height, preferredColumns: preferred)
                    XCTAssertGreaterThanOrEqual(fit.columns * fit.rows, count)
                    XCTAssertLessThanOrEqual(fit.width * Double(fit.columns) + Double(fit.columns - 1) * 10, width + 0.001)
                    XCTAssertLessThanOrEqual(fit.height * Double(fit.rows) + Double(fit.rows - 1) * 10, height + 0.001)
                }
            }
        }
    }

    func testEnvironmentParserPreservesQuotedPasswordsAndEquals() {
        let config = Connection.fromEnvironment("# local\nTVH_URL=http://localhost:9981\nTVH_USER=test\nTVH_PASS='a=# b'\nTVH_AUTH=basic # auth\n")
        XCTAssertEqual(config.password, "a=# b")
        XCTAssertEqual(config.auth, "basic")
        XCTAssertNotNil(config.baseURL)
        XCTAssertNil(Connection(address: "http://user:secret@localhost:9981", username: "", password: "").baseURL)
    }

    func testImpossibleManualColumnsFallBackToAUsableVideoWall() {
        for (width, height) in [(672.0, 330.0), (1292.0, 688.0)] {
            XCTAssertFalse(GridFit.canFit(count: 14, width: width, height: height, columns: 1))
            let fit = GridFit.calculate(count: 14, width: width, height: height, preferredColumns: 1)
            XCTAssertGreaterThan(fit.columns, 1)
            XCTAssertGreaterThanOrEqual(fit.height, 90)
            XCTAssertGreaterThan(fit.height - 56, 0)
        }
    }

    func testStreamURLPreservesProxyPrefixAndDoesNotExposeCredentials() throws {
        let api = API(connection: Connection(address: "http://localhost:9981/tvh", username: "test", password: "secret"))
        defer { api.close() }
        let url = try api.streamURL(for: Preview(id: 1, title: "test", path: "stream/service/abc", sourceState: "Running"))
        XCTAssertEqual(url.path, "/tvh/stream/service/abc")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.password)
        XCTAssertTrue(url.absoluteString.contains("weight=1"))
    }

    func testTicketPreservesLowPriorityAndRejectsAnotherServer() throws {
        let expected = URL(string: "http://localhost:9981/stream/service/abc")!
        let result = try API.authorizedStreamURL(playlist: "#EXTM3U\nhttp://localhost:9981/stream/service/abc?ticket=test&profile=pass\n", expected: expected)
        let query = URLComponents(url: result, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "weight" }?.value, "1")
        XCTAssertEqual(query.first { $0.name == "ticket" }?.value, "test")
        XCTAssertThrowsError(try API.authorizedStreamURL(playlist: "http://other.invalid/stream/service/abc?ticket=test", expected: expected))
        XCTAssertThrowsError(try API.authorizedStreamURL(playlist: "http://localhost:9981/stream/service/abc", expected: expected))
    }

    func testRealServerReadOnlyIntegration() async throws {
        guard let path = ProcessInfo.processInfo.environment["TVH_INTEGRATION_ENV"] else { throw XCTSkip("Opt-in live test: set TVH_INTEGRATION_ENV to the local .env path") }
        let config = Connection.fromEnvironment(try String(contentsOfFile: path, encoding: .utf8))
        let api = API(connection: config)
        defer { api.close() }
        let inputs: GridResponse<Input> = try await api.read("status/inputs")
        let subscriptions: GridResponse<Subscription> = try await api.read("status/subscriptions")
        let services: [Service] = try await api.all("mpegts/service/grid")
        let channels: [Channel] = try await api.all("channel/grid")
        let multiplexes: [Multiplex] = try await api.all("mpegts/mux/grid")
        XCTAssertFalse(inputs.entries.isEmpty)
        XCTAssertFalse(services.isEmpty)
        XCTAssertFalse(multiplexes.isEmpty)
        let choices = StreamChoice.catalog(services: services, channels: channels, multiplexes: multiplexes)
        XCTAssertFalse(choices.isEmpty)
        XCTAssertTrue(multiplexes.compactMap(\.frequencyMHz).allSatisfy { $0 > 0 })
        if let channel = channels.first(where: { $0.name == "ZDF HD" }) ?? channels.first {
            let schedule = try await api.programmeSchedule(channelID: channel.uuid, language: .german)
            XCTAssertTrue(schedule.events.allSatisfy { $0.channelUuid == channel.uuid })
            print("Live EPG: \(schedule.events.count) validated events for \(channel.name)")
        }
        if let channel = channels.first(where: { $0.name == "arte HD" && $0.icon_public_url != nil }) ?? channels.first(where: { $0.icon_public_url != nil }) {
            let iconURL = try XCTUnwrap(api.channelIconURL(for: channel))
            let data = try await api.channelIconData(from: iconURL)
            let image = NSImage(data: try XCTUnwrap(data))
            XCTAssertEqual(image?.isValid, true)
            print("Live channel logo: authenticated image cache and image decoding passed for \(channel.name).")
        }
        if let channel = channels.first {
            let ticket = try await api.ticketURL(for: Preview(id: 0, title: channel.name, path: "stream/channel/\(channel.uuid)", sourceState: ""))
            XCTAssertNotNil(URLComponents(url: ticket, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ticket" })
        }
        let snapshot = Snapshot.tuners(inputs: inputs.entries, subscriptions: subscriptions.entries, services: services, channels: channels)
        XCTAssertEqual(snapshot.count, inputs.entries.count)
        print("Live integration: \(snapshot.count) tuners, \(services.count) services, \(channels.count) channels; read-only API and authentication passed.")
    }
}
