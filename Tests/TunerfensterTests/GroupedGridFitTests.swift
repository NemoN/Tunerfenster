import XCTest
@testable import Tunerfenster

final class GroupedGridFitTests: XCTestCase {
    func testRowsAreCalculatedSeparatelyForEachServer() {
        XCTAssertEqual(GridFit.groupedRows(counts: [14, 8], columns: 4), 6)
        XCTAssertEqual(GridFit.groupedRows(counts: [3, 3], columns: 4), 2)
        XCTAssertEqual(GridFit.groupedRows(counts: [0, 3], columns: 4), 1)
    }

    func testLayoutReservesSpaceForEachHeaderAndGrid() {
        let counts = [14, 8]
        let fit = GridFit.calculateGroups(counts: counts, width: 1200, height: 800, preferredColumns: 4)
        XCTAssertEqual(fit.columns, 4)
        XCTAssertEqual(fit.rows, 6)
        XCTAssertEqual(fit.height * 6 + 4 * 10 + 2 * 40 + 8, 800, accuracy: 0.001)
        XCTAssertTrue(GridFit.canFitGroups(counts: counts, width: 1200, height: 800, columns: 4))
        XCTAssertFalse(GridFit.canFitGroups(counts: counts, width: 1200, height: 400, columns: 4))
    }

    func testEmptyAndOfflineGroupsRemainSafe() {
        let fit = GridFit.calculateGroups(counts: [0, 0], width: 700, height: 400)
        XCTAssertEqual(fit.rows, 0)
        XCTAssertFalse(GridFit.canFitGroups(counts: [0, 0], width: 700, height: 400, columns: 1))
        XCTAssertEqual(GridFit.groupedRows(counts: [2], columns: 0), 0)
    }
}
