import XCTest
@testable import Tunerfenster

final class TunerHeadersTests: XCTestCase {
    private let ids = ["6", "7", "8", "9"]

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
