import XCTest
@testable import Tunerfenster

final class TunerHeadersTests: XCTestCase {
    private let ids = ["6", "7", "8", "9"]

    private func tuner(_ id: String, paths: [String] = [], unresolved: Bool = false) -> Tuner {
        Tuner(input: Input(uuid: id, input: id),
              previews: paths.enumerated().map { Preview(id: $0.offset, title: $0.element, path: $0.element, sourceState: "Running") },
              hasEPG: false, unresolvedTV: unresolved)
    }

    func testManualStreamReplacesItsFollowingMirrorAndSwapsHeaders() {
        let tuners = [tuner("6"), tuner("8", paths: ["RTL"])]
        let plan = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": ["8"]],
                                              manualPaths: ["6": "RTL"], activeIDs: ["6", "8"])
        XCTAssertEqual(plan.headers, ["6": "8", "8": "6"])
        XCTAssertTrue(plan.following["8"]!.isEmpty, "The displaced free input must not play RTL a second time")
        XCTAssertEqual(plan.following.values.flatMap { $0 }.count, 0)
    }

    func testDisplacedFollowingTileUsesTheOtherPhysicalTunersChannel() {
        let tuners = [tuner("6", paths: ["ARD"]), tuner("8", paths: ["RTL"])]
        let plan = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": ["8"]],
                                              manualPaths: ["6": "RTL"], activeIDs: ["6", "8"])
        XCTAssertEqual(plan.headers, ["6": "8", "8": "6"])
        XCTAssertEqual(plan.following["8"]?.map(\.path), ["ARD"])
    }

    func testDifferentExternalChannelOnTheSharedInputRemainsAvailable() {
        let tuners = [tuner("6"), tuner("8", paths: ["RTL", "ARD"])]
        let plan = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": ["8"]],
                                              manualPaths: ["6": "RTL"], activeIDs: ["6", "8"])
        XCTAssertEqual(plan.headers, ["6": "6", "8": "8"], "Two different channels sharing an input still need routing details")
        XCTAssertEqual(plan.following["8"]?.map(\.path), ["ARD"])
    }

    func testStoppedOrAmbiguousManualStreamsDoNotHideExternalChannels() {
        let tuners = [tuner("6"), tuner("8", paths: ["RTL"]), tuner("9", paths: ["RTL"])]
        let stopped = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": ["8"]],
                                                 manualPaths: ["6": "RTL"], activeIDs: ["8"])
        XCTAssertEqual(stopped.headers["8"], "8")
        XCTAssertEqual(stopped.following["8"]?.map(\.path), ["RTL"])
        for sources in [[], ["8", "9"]] {
            let plan = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": sources],
                                                  manualPaths: ["6": "RTL"], activeIDs: ["6", "8", "9"])
            XCTAssertEqual(plan.following["8"]?.map(\.path), ["RTL"])
            XCTAssertEqual(plan.following["9"]?.map(\.path), ["RTL"])
        }
    }

    func testMovingAndClearingManualReceptionRestoresFollowingWithoutHistory() {
        let tuners = [tuner("6"), tuner("8", paths: ["RTL"]), tuner("9", paths: ["RTL"])]
        let moved = TunerHeaders.presentation(tuners: tuners, manualSources: ["6": ["9"]],
                                                manualPaths: ["6": "RTL"], activeIDs: ["6", "8", "9"])
        XCTAssertEqual(moved.headers, ["6": "9", "8": "8", "9": "6"])
        XCTAssertEqual(moved.following["8"]?.map(\.path), ["RTL"], "An independent physical input must remain visible")
        XCTAssertTrue(moved.following["9"]!.isEmpty)
        let reset = TunerHeaders.presentation(tuners: tuners, manualSources: [:], manualPaths: [:], activeIDs: ["6", "8", "9"])
        XCTAssertEqual(reset.headers, ["6": "6", "8": "8", "9": "9"])
        XCTAssertEqual(reset.following["8"]?.map(\.path), ["RTL"])
        XCTAssertEqual(reset.following["9"]?.map(\.path), ["RTL"])
    }

    func testSingleStreamSwapsHeadersWithoutMovingTiles() {
        let headers = TunerHeaders.resolve(ids: ids, sources: ["6": ["8"]])
        XCTAssertEqual(headers, ["6": "8", "8": "6", "7": "7", "9": "9"])
        XCTAssertEqual(Set(headers.values), Set(ids))
    }

    func testSeparateSwapsAndChainsKeepTheirOwnDisplacedNames() {
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["9"], "7": ["8"]]),
                       ["6": "9", "9": "6", "7": "8", "8": "7"])
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8"], "8": ["9"]]),
                       ["6": "8", "8": "9", "9": "6", "7": "7"])
    }

    func testCyclesAndAlreadyMatchingSourcesRemainUnique() {
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8"], "8": ["6"], "7": ["7"]]),
                       ["6": "8", "8": "6", "7": "7", "9": "9"])
    }

    func testSharedInputAndExternalViewerDoNotCreateMisleadingDuplicateHeaders() {
        let original = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8"], "7": ["8"]]), original)
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8"], "8": ["8"]]), original)
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["7"], "7": ["8"], "8": ["8"]]), original)
    }

    func testUnknownOrMultipleSourcesPreserveNamesInTheirComponent() {
        let original = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8"], "8": []]), original)
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["8", "9"]]), original)
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": ["missing"]]), original)
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: ["6": [], "7": ["9"]]),
                       ["6": "6", "7": "9", "9": "7", "8": "8"])
    }

    func testSourceChangesRecomputeHeadersWithoutHistoryOrInputOrderDependence() {
        let moved = TunerHeaders.resolve(ids: ids, sources: ["6": ["9"]])
        XCTAssertEqual(moved, TunerHeaders.resolve(ids: ids.reversed(), sources: ["6": ["9"]]))
        XCTAssertEqual(moved["8"], "8")
        XCTAssertEqual(moved["9"], "6")
        XCTAssertEqual(TunerHeaders.resolve(ids: ids, sources: [:]), Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }))
    }
}
