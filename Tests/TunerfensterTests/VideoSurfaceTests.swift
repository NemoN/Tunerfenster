import AppKit
import XCTest
@testable import Tunerfenster

final class VideoSurfaceTests: XCTestCase {
    @MainActor func testOnlyTheCurrentHostResizesTheCanvasDuringAFullScreenTransition() {
        let canvas = VideoCanvas(frame: .zero)
        let windowed = VideoHost(canvas: canvas)
        windowed.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        windowed.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.frame, windowed.bounds)

        let fullScreen = VideoHost(canvas: canvas)
        fullScreen.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        fullScreen.layoutSubtreeIfNeeded()
        windowed.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        windowed.needsLayout = true
        windowed.layoutSubtreeIfNeeded()

        XCTAssertTrue(canvas.superview === fullScreen)
        XCTAssertEqual(canvas.frame, fullScreen.bounds)
    }
}
