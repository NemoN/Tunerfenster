import AppKit
import SwiftUI
import XCTest
@testable import Tunerfenster

final class DetailsSplitTests: XCTestCase {
    @MainActor func testPanelIndicatorsUseOverlayScrollersWithoutChangingSystemPreferences() {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .legacy
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 800))
        let probe = AutomaticScrollIndicators.Probe()
        document.addSubview(probe)
        scroll.documentView = document
        probe.configure()
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertTrue(scroll.autohidesScrollers)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertEqual(document.frame.height, 800)
        probe.hideIndicators()
        XCTAssertEqual(scroll.verticalScroller?.isHidden, true)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 120)
        XCTAssertEqual(scroll.verticalScroller?.isHidden, false)
    }

    @MainActor func testCompactDetailsKeepTheirHorizontalProportionsWhenTheWindowResizes() async {
        _ = NSApplication.shared
        let controller = RecordingSplitController(), split = RecordingDividerView()
        split.isVertical = true
        controller.splitView = split
        let first = NSSplitViewItem(viewController: NSHostingController(rootView: Color.clear))
        first.minimumThickness = 280
        first.holdingPriority = .defaultLow
        let second = NSSplitViewItem(viewController: NSHostingController(rootView: Color.clear))
        second.minimumThickness = 160
        second.holdingPriority = .defaultLow
        controller.addSplitViewItem(first); controller.addSplitViewItem(second)
        controller.initialDivision = (0.7, 280, 160, 672)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 672, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 672, height: 300))
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(split.subviews[0].frame.width, (672 - 11) * 0.7, accuracy: 1)
        XCTAssertEqual(split.subviews[1].frame.width, (672 - 11) * 0.3, accuracy: 1)

        window.setContentSize(NSSize(width: 920, height: 300))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(split.subviews[0].frame.width, (920 - 11) * 0.7, accuracy: 2)
        XCTAssertEqual(split.subviews[1].frame.width, (920 - 11) * 0.3, accuracy: 2)

        split.setPosition(450, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let adjusted = split.subviews[0].frame.width / (920 - 11)
        window.setContentSize(NSSize(width: 760, height: 300))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(split.subviews[0].frame.width, (760 - 11) * adjusted, accuracy: 2)
    }

    @MainActor func testInitialDivisionWaitsForRealSizeAndDoesNotOverrideLaterResizing() async {
        _ = NSApplication.shared
        let controller = RecordingSplitController()
        let split = RecordingDividerView()
        split.isVertical = false
        controller.splitView = split
        let first = NSSplitViewItem(viewController: NSHostingController(rootView: Color.clear))
        first.minimumThickness = 100
        first.holdingPriority = NSLayoutConstraint.Priority(260)
        let second = NSSplitViewItem(viewController: NSHostingController(rootView: Color.clear))
        second.minimumThickness = 104
        controller.addSplitViewItem(first)
        controller.addSplitViewItem(second)
        controller.initialDivision = (0.84, 100, 104, 800)
        controller.viewDidLayout()
        XCTAssertNotNil(controller.initialDivision)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 800),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 320, height: 800))
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        XCTAssertNil(controller.initialDivision)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(split.subviews[0].frame.height, (800 - 11) * 0.84, accuracy: 1)

        split.setPosition(400, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        XCTAssertEqual(split.subviews[0].frame.height, 400, accuracy: 1)
    }
}
