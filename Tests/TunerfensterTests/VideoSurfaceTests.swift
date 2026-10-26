import AppKit
import XCTest
@testable import Tunerfenster

final class VideoSurfaceTests: XCTestCase {
    @MainActor func testFullScreenUsesAnOpaqueBlackWindowAndRestoresWindowedAppearance() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.isOpaque = false
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        let controller = PlaybackWindow()
        controller.attach(window)
        defer { controller.detach(); window.close() }

        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        XCTAssertTrue(controller.fullScreen)
        XCTAssertEqual(window.backgroundColor, .black)
        XCTAssertTrue(window.isOpaque)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)

        NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
        XCTAssertFalse(controller.fullScreen)
        XCTAssertEqual(window.backgroundColor, .black)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertEqual(window.backgroundColor, .white)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)

        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        controller.detach()
        XCTAssertEqual(window.backgroundColor, .white)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.titleVisibility, .visible)
    }

    @MainActor func testCurrentSurfaceOwnsDoubleClicksAndReplacesItsActionWithoutAddingRecognizers() {
        let canvas = VideoCanvas(frame: .zero)
        let original = VideoHost(canvas: canvas)
        var first = 0, second = 0
        original.setDoubleClickAction { first += 1 }
        original.invokeDoubleClick()
        XCTAssertEqual(first, 1)
        let fullscreen = VideoHost(canvas: canvas)
        fullscreen.setDoubleClickAction { second += 1 }
        original.invokeDoubleClick()
        fullscreen.invokeDoubleClick()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        fullscreen.setDoubleClickAction { second += 10 }
        fullscreen.invokeDoubleClick()
        XCTAssertEqual(second, 11)
        XCTAssertEqual(fullscreen.gestureRecognizers.count, 1)
        let click = fullscreen.gestureRecognizers.first as? NSClickGestureRecognizer
        XCTAssertEqual(click?.numberOfClicksRequired, 2)
        XCTAssertEqual(click?.buttonMask, 1)
        fullscreen.setDoubleClickAction(nil)
        XCTAssertEqual(click?.isEnabled, false)
    }

    @MainActor func testUnroundedFullscreenSurfaceIsOpaqueClippedAndAvoidsRedundantCanvasResizing() {
        let canvas = VideoCanvas(frame: .zero)
        let surface = VideoHost(canvas: canvas)
        surface.setCornerRadius(0)
        surface.frame = NSRect(x: 0, y: 0, width: 640.5, height: 360.5)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.isOpaque)
        XCTAssertEqual(surface.layer?.masksToBounds, true)
        XCTAssertTrue(canvas.frame.contains(surface.bounds))
        canvas.postsFrameChangedNotifications = true
        var changes = 0
        let observation = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: canvas, queue: nil) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observation) }
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(changes, 0)
    }

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
