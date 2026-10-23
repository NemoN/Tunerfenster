import XCTest
@testable import Tunerfenster

final class TunerAllocationTests: XCTestCase {
    func tuner(_ name: String) -> Tuner {
        Tuner(input: Input(uuid: name, input: name), previews: [], hasEPG: false, unresolvedTV: false)
    }

    func choice(_ id: String, frequency: Double, system: String = "DVB-S2", polarisation: String = "H", mapped: Bool = true) -> StreamChoice {
        let satellite = system.hasPrefix("DVB-S")
        return StreamChoice(service: Service(uuid: id, network: "Network", multiplex_uuid: "mux-" + id),
                            name: id, mapped: mapped,
                            multiplex: Multiplex(uuid: "mux-" + id, network: "Network", delsys: system,
                                                 frequency: frequency, polarisation: satellite ? polarisation : nil,
                                                 orbital: satellite ? "19.2E" : nil))
    }

    func testThirteenPreviewsUseTwelveSatelliteCarriersAndOneCableCarrier() {
        let tuners = (1...12).map { tuner("DVB-S2 #\($0)") } + [tuner("DVB-C #13")]
        let sat = (1...12).map { choice("Channel \($0)", frequency: 11_000_000 + Double($0) * 50_000) }
        let cable = choice("Cable", frequency: 546_000_000, system: "DVB-C/ANNEX_A")
        let current = Dictionary(uniqueKeysWithValues: tuners.dropLast().enumerated().map { ($0.element.id, sat[$0.offset % 7]) })
        let plan = TunerAllocation.plan(tuners: tuners, choices: sat + [cable], current: current)
        XCTAssertEqual(plan.targetCount, 13)
        XCTAssertEqual(plan.assignments.count, 13)
        XCTAssertEqual(Set(plan.assignments.values.compactMap(TunerAllocation.carrierKey)).count, 13)
        XCTAssertEqual(plan.assignments["DVB-C #13"]?.id, cable.id)
        for item in tuners {
            XCTAssertEqual(plan.assignments[item.id]?.matches(input: item.input), true)
        }
        let repeated = TunerAllocation.plan(tuners: tuners, choices: sat + [cable], current: plan.assignments)
        XCTAssertEqual(repeated.assignments.mapValues(\.id), plan.assignments.mapValues(\.id), "A second click should retain an already diverse selection")
    }

    func testSeveralChannelsOrDuplicateMuxRecordsOnOneCarrierDoNotFillSeveralTuners() {
        let a = choice("A", frequency: 11_362_000)
        let b = choice("B", frequency: 11_362_000, system: "DVB-S")
        XCTAssertEqual(TunerAllocation.carrierKey(for: a), TunerAllocation.carrierKey(for: b))
        let plan = TunerAllocation.plan(tuners: [tuner("DVB-S2 #1"), tuner("DVB-S2 #2")], choices: [a, b], current: [:])
        XCTAssertEqual(plan.assignments.count, 1)
        let vertical = choice("V", frequency: 11_362_000, polarisation: "V")
        XCTAssertNotEqual(TunerAllocation.carrierKey(for: a), TunerAllocation.carrierKey(for: vertical))
    }

    func testMatchingCanMoveAnExistingHybridChoiceToLeaveTheOnlySatelliteCarrierForASatelliteInput() {
        let hybrid = tuner("Hybrid input"), satellite = tuner("DVB-S2 input")
        let sat = choice("Satellite", frequency: 11_362_000)
        let cable = choice("Cable", frequency: 546_000_000, system: "DVB-C/ANNEX_A")
        let plan = TunerAllocation.plan(tuners: [hybrid, satellite], choices: [sat, cable], current: [hybrid.id: sat])
        XCTAssertEqual(plan.assignments.count, 2)
        XCTAssertEqual(plan.assignments[satellite.id]?.id, sat.id)
        XCTAssertEqual(plan.assignments[hybrid.id]?.id, cable.id)
    }

    func testDistinctExistingSelectionsAreKeptAndMissingDataIsNotTreatedAsAnotherFrequency() {
        let first = tuner("DVB-S2 #1"), second = tuner("DVB-S2 #2")
        let a = choice("A", frequency: 11_362_000), b = choice("B", frequency: 12_480_000)
        let unmapped = choice("Unmapped", frequency: 11_494_000, mapped: false)
        let unknown = StreamChoice(service: Service(uuid: "Unknown"), name: "Unknown", mapped: true, multiplex: nil)
        let plan = TunerAllocation.plan(tuners: [first, second], choices: [a, b, unmapped, unknown], current: [first.id: b, second.id: a])
        XCTAssertEqual(plan.assignments.mapValues(\.id), [first.id: b.id, second.id: a.id])
        XCTAssertNil(TunerAllocation.carrierKey(for: unknown))
        XCTAssertNil(TunerAllocation.carrierKey(for: choice("Invalid", frequency: .nan)))
        XCTAssertTrue(TunerAllocation.plan(tuners: [first], choices: [unmapped, unknown], current: [:]).assignments.isEmpty)
        XCTAssertTrue(TunerAllocation.plan(tuners: [], choices: [a], current: [:]).assignments.isEmpty)
    }
}
