import AppKit
import SwiftUI

/// Keep these panels' indicators transient even when macOS prefers legacy bars.
struct AutomaticScrollIndicators: NSViewRepresentable {
    final class Probe: NSView {
        private weak var scroll: NSScrollView?
        private var observations = [NSObjectProtocol]()
        private var hide: DispatchWorkItem?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleConfiguration()
        }
        func scheduleConfiguration() {
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }
        func configure() {
            guard let enclosing = enclosingScrollView else { return }
            if enclosing.scrollerStyle != .overlay { enclosing.scrollerStyle = .overlay }
            enclosing.autohidesScrollers = true
            guard scroll !== enclosing else { return }
            observations.forEach(NotificationCenter.default.removeObserver)
            observations = []
            scroll = enclosing
            enclosing.contentView.postsFrameChangedNotifications = true
            enclosing.contentView.postsBoundsChangedNotifications = true
            for notification in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: notification,
                    object: enclosing.contentView, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.indicatorActivity() }
                    })
            }
            indicatorActivity()
        }
        private func indicatorActivity() {
            guard let scroll else { return }
            if let document = scroll.documentView {
                scroll.verticalScroller?.isHidden = document.frame.height <= scroll.contentView.bounds.height
                scroll.horizontalScroller?.isHidden = document.frame.width <= scroll.contentView.bounds.width
            }
            scheduleHiding()
        }
        private func scheduleHiding() {
            hide?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // A scrollbar remains usable throughout a drag.
                if NSEvent.pressedMouseButtons & 1 != 0 { self.scheduleHiding() }
                else { self.hideIndicators() }
            }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
        func hideIndicators() {
            // Overlay scrollers otherwise stay expanded while the pointer rests
            // beside a divider, even after resizing has finished.
            scroll?.verticalScroller?.isHidden = true
            scroll?.horizontalScroller?.isHidden = true
        }
        deinit {
            hide?.cancel()
            observations.forEach(NotificationCenter.default.removeObserver)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.scheduleConfiguration() }
}
