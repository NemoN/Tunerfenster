import XCTest
@testable import Tunerfenster

final class PlaybackControlsVisibilityTests: XCTestCase {
    func testMovementShowsControlsAndRestartsTheThreeSecondDeadline() {
        var state = PlaybackControlsState()
        state.setActive(true, now: 0)
        state.activity(now: 2, pointerMoved: true)
        state.expire(now: 4.9)
        XCTAssertTrue(state.visible)
        state.expire(now: 5)
        XCTAssertFalse(state.visible)
        state.interact(false, now: 6) // Removing a hidden view must not reveal it again.
        XCTAssertFalse(state.visible)
        state.activity(now: 7, pointerMoved: true)
        XCTAssertTrue(state.visible)
    }

    func testDraggingKeepsTheControlsVisibleUntilReleased() {
        var state = PlaybackControlsState()
        state.setActive(true, now: 0)
        state.interact(true, now: 2)
        state.expire(now: 50)
        XCTAssertTrue(state.visible)
        state.expire(now: 60)
        XCTAssertTrue(state.visible)
        state.interact(false, now: 60)
        state.expire(now: 62.9)
        XCTAssertTrue(state.visible)
        state.expire(now: 63)
        XCTAssertFalse(state.visible)
    }

    func testKeyboardNavigationKeepsControlsVisibleUntilTheMouseTakesOver() {
        var state = PlaybackControlsState()
        state.setActive(true, now: 0)
        state.useKeyboard(now: 1)
        state.expire(now: 100)
        XCTAssertTrue(state.visible)
        state.activity(now: 100, pointerMoved: true)
        state.expire(now: 103)
        XCTAssertFalse(state.visible)
    }

    func testVoiceOverPreventsAutomaticHidingWithoutShowingControlsOutsideFullScreen() {
        var state = PlaybackControlsState()
        state.useAccessibility(true, now: 0)
        XCTAssertFalse(state.visible)
        state.setActive(true, now: 1)
        state.expire(now: 100)
        XCTAssertTrue(state.visible)
        state.useAccessibility(false, now: 100)
        state.expire(now: 103)
        XCTAssertFalse(state.visible)
    }

    func testLeavingAndReenteringFullScreenClearsInteractionAndOldDeadlines() {
        var state = PlaybackControlsState()
        state.setActive(true, now: 0)
        state.interact(true, now: 1)
        state.setActive(false, now: 2)
        state.activity(now: 100, pointerMoved: true)
        XCTAssertFalse(state.visible)
        state.setActive(true, now: 100)
        state.expire(now: 101)
        XCTAssertTrue(state.visible)
        state.expire(now: 103)
        XCTAssertFalse(state.visible)
    }
}
