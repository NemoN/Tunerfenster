import XCTest
import AppKit
@testable import Tunerfenster

final class RecordingTimelineTests: XCTestCase {
    func testProgressEndsAtPlayheadAndIsClampedToBar() {
        let bar = NSRect(x: 10, y: 4, width: 200, height: 6)
        XCTAssertEqual(RecordingTimeline.Cell.progressRect(bar: bar, knobCenter: 60).width, 50)
        XCTAssertEqual(RecordingTimeline.Cell.progressRect(bar: bar, knobCenter: 0).width, 0)
        XCTAssertEqual(RecordingTimeline.Cell.progressRect(bar: bar, knobCenter: 300).width, 200)
    }
}
