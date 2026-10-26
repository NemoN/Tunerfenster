import SwiftUI
import AppKit

/// Observes the SwiftUI-owned window without replacing its delegate.
@MainActor
final class PlaybackWindow: ObservableObject {
    @Published private(set) var fullScreen = false
    let controls = PlaybackControlsVisibility()
    private weak var window: NSWindow?
    private var notifications = [NSObjectProtocol]()
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var acceptedMouseMovement = false
    private var transitioning = false
    private var openPanels = 0
    private var trackingMenus = 0
    private var windowAppearance: (color: NSColor, opaque: Bool, transparentTitle: Bool, title: NSWindow.TitleVisibility)?
    private var videoFullScreen: (frame: NSRect, style: NSWindow.StyleMask, shadow: Bool, presentation: NSApplication.PresentationOptions)?
    var focused = false
    var videoAvailable = false
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
        acceptedMouseMovement = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        fullScreen = window.styleMask.contains(.fullScreen)
        controls.setActive(fullScreen)
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreVideoFullScreen() }
        })
        notifications.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreVideoFullScreen() }
        })
        notifications.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackingMenus += 1 }
        })
        notifications.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.trackingMenus = max(0, self.trackingMenus - 1) } }
        })
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            notifications.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.transitioning = true
                    let entering = notification.name == NSWindow.willEnterFullScreenNotification
                    if entering { self?.prepareFullScreenAppearance() }
                    // Settle the toolbar and video hierarchy before AppKit animates
                    // the window, avoiding a second replacement after the transition.
                    self?.fullScreen = entering
                    self?.controls.setActive(entering)
                }
            })
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            notifications.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    self?.transitioning = false
                    self?.fullScreen = window?.styleMask.contains(.fullScreen) == true
                    self?.controls.setActive(self?.fullScreen == true)
                    if self?.fullScreen == false { self?.restoreWindowAppearance() }
                }
            })
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
        // Pointer activity also arrives from VLC's embedded child views.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handlePointer(event)
            }
        }
    }

    func detach() {
        restoreVideoFullScreen()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications = []
        trackingMenus = 0
        window?.acceptsMouseMovedEvents = acceptedMouseMovement
        controls.setActive(false)
        restoreWindowAppearance()
        window = nil
    }

    private func prepareFullScreenAppearance() {
        guard let window, windowAppearance == nil else { return }
        windowAppearance = (window.backgroundColor, window.isOpaque, window.titlebarAppearsTransparent, window.titleVisibility)
        window.backgroundColor = .black
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    private func restoreWindowAppearance() {
        guard let window, let appearance = windowAppearance else { return }
        window.backgroundColor = appearance.color
        window.isOpaque = appearance.opaque
        window.titlebarAppearsTransparent = appearance.transparentTitle
        window.titleVisibility = appearance.title
        windowAppearance = nil
    }

    func toggleFullScreen() {
        guard let window, !transitioning, window.attachedSheet == nil,
              !blocked, openPanels == 0, trackingMenus == 0 else { return }
        if videoFullScreen != nil {
            restoreVideoFullScreen()
            return
        }
        // Keep the video in the same window during channel changes. Moving the
        // embedded drawable into a native fullscreen Space can leave a stale edge.
        if videoAvailable, !window.styleMask.contains(.fullScreen), let screen = window.screen {
            videoFullScreen = (window.frame, window.styleMask, window.hasShadow, NSApp.presentationOptions)
            prepareFullScreenAppearance()
            fullScreen = true
            controls.setActive(true)
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
            window.styleMask = [.borderless, .resizable]
            window.hasShadow = false
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.toggleFullScreen(nil)
    }

    private func restoreVideoFullScreen() {
        guard let window, let previous = videoFullScreen else { return }
        videoFullScreen = nil
        fullScreen = false
        controls.setActive(false)
        NSApp.presentationOptions = previous.presentation
        window.styleMask = previous.style
        window.hasShadow = previous.shadow
        window.setFrame(previous.frame, display: true)
        restoreWindowAppearance()
    }

    private func handlePointer(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        if fullScreen, !blocked, openPanels == 0, trackingMenus == 0 {
            controls.activity(pointerMoved: true)
        }
        return event
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, NSApp.keyWindow === window,
              window.attachedSheet == nil, !blocked, openPanels == 0, trackingMenus == 0 else { return event }
        if fullScreen {
            controls.activity()
            if event.keyCode == 48 { controls.useKeyboard() }
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 3, modifiers == [.command, .control] {
            if !event.isARepeat { toggleFullScreen() }
            return nil
        }
        guard (window.firstResponder as? NSTextView)?.isEditable != true,
              modifiers.isEmpty else { return event }
        if event.charactersIgnoringModifiers?.lowercased() == "m" {
            if !event.isARepeat { toggleMute() }
            return nil
        }
        if event.keyCode == 53 {
            if transitioning || event.isARepeat { return nil }
            if fullScreen || window.styleMask.contains(.fullScreen) {
                toggleFullScreen()
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
    let videoAvailable: Bool
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
        controller.videoAvailable = videoAvailable
        controller.blocked = blocked
        controller.leaveZoom = leaveZoom
        controller.switchChannel = switchChannel
        controller.toggleMute = toggleMute
    }

    static func dismantleNSView(_ nsView: WindowProbe, coordinator: ()) { nsView.controller?.detach() }
}
