import SwiftUI
import AppKit

/// Observes the SwiftUI-owned window without replacing its delegate.
@MainActor
final class PlaybackWindow: ObservableObject {
    @Published private(set) var fullScreen = false
    private weak var window: NSWindow?
    private var notifications = [NSObjectProtocol]()
    private var keyMonitor: Any?
    private var transitioning = false
    private var openPanels = 0
    private var trackingMenus = 0
    var focused = false
    var blocked = false
    var leaveZoom: () -> Void = {}
    var switchChannel: (Int) -> Void = { _ in }
    var toggleMute: () -> Void = {}

    func panelOpened() { openPanels += 1 }
    func panelClosed() { openPanels = max(0, openPanels - 1) }

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        detach()
        guard let window else { return }
        self.window = window
        fullScreen = window.styleMask.contains(.fullScreen)
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackingMenus += 1 }
        })
        notifications.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.trackingMenus = max(0, self.trackingMenus - 1) } }
        })
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            notifications.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.transitioning = true }
            })
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            notifications.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    self?.transitioning = false
                    self?.fullScreen = window?.styleMask.contains(.fullScreen) == true
                }
            })
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    func detach() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications = []
        trackingMenus = 0
        window = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, NSApp.keyWindow === window,
              window.attachedSheet == nil, !blocked, openPanels == 0, trackingMenus == 0,
              (window.firstResponder as? NSTextView)?.isEditable != true,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
        if event.charactersIgnoringModifiers?.lowercased() == "m" {
            if !event.isARepeat { toggleMute() }
            return nil
        }
        if event.keyCode == 53 {
            if transitioning || event.isARepeat { return nil }
            if fullScreen || window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return nil
            }
            if focused { leaveZoom(); return nil }
        }
        if focused && !transitioning && (event.keyCode == 125 || event.keyCode == 126) {
            switchChannel(event.keyCode == 126 ? -1 : 1)
            return nil
        }
        return event
    }
}

private struct PlaybackPanel: ViewModifier {
    @EnvironmentObject private var window: PlaybackWindow
    func body(content: Content) -> some View {
        content.onAppear { window.panelOpened() }.onDisappear { window.panelClosed() }
    }
}

extension View {
    func playbackPanel() -> some View { modifier(PlaybackPanel()) }
}

struct PlaybackWindowBridge: NSViewRepresentable {
    let controller: PlaybackWindow
    let focused: Bool
    let blocked: Bool
    let leaveZoom: () -> Void
    let switchChannel: (Int) -> Void
    let toggleMute: () -> Void

    final class WindowProbe: NSView {
        weak var controller: PlaybackWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Window notifications can publish SwiftUI state, so attach after this update.
            DispatchQueue.main.async { [weak self] in self?.controller?.attach(self?.window) }
        }
    }

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: WindowProbe, context: Context) {
        controller.focused = focused
        controller.blocked = blocked
        controller.leaveZoom = leaveZoom
        controller.switchChannel = switchChannel
        controller.toggleMute = toggleMute
    }

    static func dismantleNSView(_ nsView: WindowProbe, coordinator: ()) { nsView.controller?.detach() }
}
