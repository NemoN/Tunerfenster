import AppKit
import SwiftUI

/// Keeps AppKit's divider tracking, accessibility and autosaving, with only a dot drawn.
final class RecordingDividerView: NSSplitView {
    override var isOpaque: Bool { false }
    override var dividerThickness: CGFloat { 11 }
    override var dividerColor: NSColor { .clear }

    override func drawDivider(in rect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)).fill()
    }
}

struct RecordingSplitView<First: View, Second: View>: NSViewControllerRepresentable {
    let name: String
    let isVertical: Bool
    let minimumFirst: CGFloat
    let minimumSecond: CGFloat
    var initialFraction: CGFloat = 0.45
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        let split = RecordingDividerView()
        split.isVertical = isVertical
        controller.splitView = split
        let firstHost = NSHostingController(rootView: AnyView(first().environment(\.self, context.environment)))
        let secondHost = NSHostingController(rootView: AnyView(second().environment(\.self, context.environment)))
        let firstItem = NSSplitViewItem(viewController: firstHost)
        firstItem.minimumThickness = minimumFirst
        firstItem.preferredThicknessFraction = initialFraction
        firstItem.holdingPriority = NSLayoutConstraint.Priority(260)
        let secondItem = NSSplitViewItem(viewController: secondHost)
        secondItem.minimumThickness = minimumSecond
        controller.addSplitViewItem(firstItem)
        controller.addSplitViewItem(secondItem)
        split.autosaveName = name
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        // Retain the hosting controllers so resizing and catalogue refreshes keep view state.
        (controller.splitViewItems[0].viewController as? NSHostingController<AnyView>)?.rootView =
            AnyView(first().environment(\.self, context.environment))
        (controller.splitViewItems[1].viewController as? NSHostingController<AnyView>)?.rootView =
            AnyView(second().environment(\.self, context.environment))
    }
}
