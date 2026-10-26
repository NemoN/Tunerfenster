import XCTest
@testable import Tunerfenster

final class StreamThroughputTests: XCTestCase {
    func testAddsStreamsAndHandlesStartsAndStops() {
        var sampler = StreamThroughputSampler()
        let first = UUID(), second = UUID(), replacement = UUID()
        XCTAssertEqual(sampler.update([first: 100, second: 200], at: 10), 0)
        XCTAssertEqual(sampler.update([first: 1_000_100, second: 500_200], at: 12), 6, accuracy: 0.0001)
        XCTAssertEqual(sampler.update([first: 1_500_100, replacement: 40], at: 13), 4, accuracy: 0.0001)
        XCTAssertEqual(sampler.update([:], at: 14), 0)
    }

    func testCounterWrapAndZeroTime() {
        var sampler = StreamThroughputSampler()
        let stream = UUID()
        _ = sampler.update([stream: UInt32.max - 99], at: 1)
        XCTAssertEqual(sampler.update([stream: 100], at: 2), 0.0016, accuracy: 0.000001)
        XCTAssertEqual(sampler.update([stream: 200], at: 2), 0)
    }
}
