import XCTest
@testable import Tunerfenster

final class EncryptedStreamTests: XCTestCase {
    func testServiceEncryptionFlagDecodesTrueFalseAndMissingValues() throws {
        let decoder = JSONDecoder()
        for (field, expected) in [("true", true), ("false", false), ("null", false)] {
            let json = Data("{\"uuid\":\"service\",\"encrypted\":\(field)}".utf8)
            let service = try decoder.decode(Service.self, from: json)
            XCTAssertEqual(StreamChoice(service: service, name: "Channel", mapped: true, multiplex: nil).preview.encrypted, expected)
        }
        let unknown = try decoder.decode(Service.self, from: Data("{\"uuid\":\"service\"}".utf8))
        XCTAssertNil(unknown.encrypted)
        XCTAssertFalse(StreamChoice(service: unknown, name: "Unknown", mapped: true, multiplex: nil).preview.encrypted)
    }

    func testFollowingKeepsEncryptionOnTheSelectedServiceRatherThanTheWholeTuner() {
        let input = Input(uuid: "input", input: "MaxLinear DVB-S/S2 #6")
        let encrypted = Service(uuid: "encrypted", network: "Sat", multiplex: "12345H", svcname: "Pay TV", encrypted: true)
        let free = Service(uuid: "free", network: "Sat", multiplex: "12345H", svcname: "Free TV", encrypted: false)
        let subscriptions = [encrypted, free].enumerated().map { index, service in
            Subscription(id: index + 1, service: input.input + "/" + service.path, client: "External viewer")
        }
        let tuner = Snapshot.tuners(inputs: [input], subscriptions: subscriptions, services: [encrypted, free], channels: [])[0]
        XCTAssertEqual(tuner.previews.map(\.encrypted), [true, false])
        XCTAssertEqual(tuner.previews.map(\.path), ["stream/service/encrypted", "stream/service/free"])
        let epg = Subscription(id: 3, service: input.input + "/Raw PID Subscription", title: "epggrab")
        let idle = Snapshot.tuners(inputs: [input], subscriptions: [epg], services: [encrypted, free], channels: [])[0]
        XCTAssertTrue(idle.previews.isEmpty)
    }

    func testManualStreamKeepsItsEncryptionFlagThroughTunerHeaderSwapping() {
        let choice = StreamChoice(service: .init(uuid: "encrypted", encrypted: true), name: "Pay TV", mapped: true, multiplex: nil)
        let first = Tuner(input: .init(uuid: "first", input: "DVB-S2 #6"), previews: [], hasEPG: false, unresolvedTV: false)
        let second = Tuner(input: .init(uuid: "second", input: "DVB-S2 #8"), previews: [choice.preview], hasEPG: false, unresolvedTV: false)
        let plan = TunerHeaders.presentation(tuners: [first, second], manualSources: [first.id: [second.id]],
                                            manualPaths: [first.id: choice.preview.path], activeIDs: [first.id, second.id])
        XCTAssertEqual(plan.headers[first.id], second.id)
        XCTAssertEqual(plan.headers[second.id], first.id)
        XCTAssertTrue(choice.preview.encrypted)
        XCTAssertTrue(plan.following[second.id]?.isEmpty == true, "The idle swapped tile must not display the stream or its key")
    }
}
