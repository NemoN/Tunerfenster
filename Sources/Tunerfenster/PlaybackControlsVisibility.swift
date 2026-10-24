import Foundation
import Combine

struct PlaybackControlsState {
    static let timeout: TimeInterval = 3
    private(set) var active = false
    private(set) var visible = false
    private var deadline: TimeInterval = 0
    private var interacting = false
    private var keyboard = false
    private var accessibility = false

    mutating func setActive(_ value: Bool, now: TimeInterval) {
        active = value; visible = value
        interacting = false; keyboard = false
        deadline = now + Self.timeout
    }
    mutating func activity(now: TimeInterval, pointerMoved: Bool = false) {
        guard active else { return }
        if pointerMoved { keyboard = false }
        visible = true; deadline = now + Self.timeout
    }
    mutating func interact(_ value: Bool, now: TimeInterval) {
        guard interacting != value else { return }
        interacting = value; activity(now: now)
    }
    mutating func useKeyboard(now: TimeInterval) {
        keyboard = true; activity(now: now)
    }
    mutating func useAccessibility(_ value: Bool, now: TimeInterval) {
        guard accessibility != value else { return }
        accessibility = value; activity(now: now)
    }
    func hideDelay(now: TimeInterval) -> TimeInterval? {
        guard active, visible, !interacting, !keyboard, !accessibility else { return nil }
        return max(0, deadline - now)
    }
    mutating func expire(now: TimeInterval) {
        if hideDelay(now: now) == 0 { visible = false }
    }
}

@MainActor
final class PlaybackControlsVisibility: ObservableObject {
    @Published private(set) var visible = false
    private var state = PlaybackControlsState()
    private var hideTask: Task<Void, Never>?
    private var timerToken = UUID()
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func setActive(_ active: Bool) {
        if !active { hideTask?.cancel(); hideTask = nil; timerToken = UUID() }
        state.setActive(active, now: now); update()
    }
    func activity(pointerMoved: Bool = false) { state.activity(now: now, pointerMoved: pointerMoved); update() }
    func interact(_ value: Bool) { state.interact(value, now: now); update() }
    func useKeyboard() { state.useKeyboard(now: now); update() }
    func useAccessibility(_ value: Bool) { state.useAccessibility(value, now: now); update() }

    private func update() {
        if visible != state.visible { visible = state.visible }
        guard hideTask == nil, state.hideDelay(now: now) != nil else { return }
        let token = UUID(); timerToken = token
        // Mouse movement updates a deadline; it does not allocate a task per event.
        hideTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.state.hideDelay(now: self?.now ?? 0) else { break }
                if delay == 0 {
                    guard let self else { break }
                    self.state.expire(now: self.now)
                    if self.visible != self.state.visible { self.visible = self.state.visible }
                    break
                }
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
            }
            if self?.timerToken == token { self?.hideTask = nil }
        }
    }
}
