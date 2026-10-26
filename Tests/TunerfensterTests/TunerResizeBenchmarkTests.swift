import XCTest
@testable import Tunerfenster

final class TunerResizeBenchmarkTests: XCTestCase {
    @MainActor func testRepeatedHeaderQueries() {
        let monitor = Monitor()
        monitor.connected = true
        monitor.tuners = (0..<14).map { index in
            Tuner(input: Input(uuid: String(index), input: "Tuner #\(index)"), previews: [], hasEPG: false, unresolvedTV: false)
        }
        let start = CFAbsoluteTimeGetCurrent()
        var count = 0
        for _ in 0..<400 {
            for tuner in monitor.tuners { count += monitor.headerTuner(for: tuner).id.count }
        }
        print("Header benchmark: \(CFAbsoluteTimeGetCurrent() - start) seconds")
        XCTAssertGreaterThan(count, 0)
    }
}

extension TunerResizeBenchmarkTests {
    @MainActor func testPresentationCacheFollowsTunerAndConnectionChanges() {
        let monitor = Monitor()
        let first = Tuner(input: Input(uuid: "1", input: "Tuner #1"), previews: [], hasEPG: false, unresolvedTV: false)
        let preview = Preview(id: 7, title: "News", path: "channel/news", sourceState: "Running")
        let second = Tuner(input: Input(uuid: "2", input: "Tuner #2"), previews: [preview], hasEPG: false, unresolvedTV: false)
        monitor.connected = true; monitor.tuners = [first, second]
        XCTAssertEqual(monitor.followingPreviews(for: second).map(\.path), ["channel/news"])
        monitor.tuners = [first]
        XCTAssertEqual(monitor.headerTuner(for: first).id, first.id)
        monitor.connected = false
        XCTAssertTrue(monitor.followingPreviews(for: first).isEmpty)
        XCTAssertEqual(first.input.tunerNumber, "#1")
        XCTAssertNil(Input(uuid: "3", input: "USB tuner").tunerNumber)
    }
}
