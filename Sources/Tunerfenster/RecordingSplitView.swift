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

final class RecordingSplitController: NSSplitViewController {
    var initialDivision: (fraction: CGFloat, minimumFirst: CGFloat, minimumSecond: CGFloat, length: CGFloat)?

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let division = initialDivision, view.window != nil else { return }
        let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let available = length - splitView.dividerThickness
        guard length >= division.length - 1,
              available >= division.minimumFirst + division.minimumSecond else { return }
        // SwiftUI initially hosts this controller at its minimum height.
        // Wait for the real size and AppKit's first constraint pass to finish.
        initialDivision = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            let length = self.splitView.isVertical ? self.splitView.bounds.width : self.splitView.bounds.height
            let available = length - self.splitView.dividerThickness
            self.splitView.setPosition(max(division.minimumFirst,
                                           min(available - division.minimumSecond, available * division.fraction)),
                                       ofDividerAt: 0)
        }
    }
}

struct RecordingSplitView<First: View, Second: View>: NSViewControllerRepresentable {
    let name: String
    let isVertical: Bool
    let minimumFirst: CGFloat
    let minimumSecond: CGFloat
    var initialFraction: CGFloat = 0.45
    var initialLength: CGFloat? = nil
    var proportionalResize = false
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = RecordingSplitController()
        let split = RecordingDividerView()
        split.isVertical = isVertical
        controller.splitView = split
        let firstHost = NSHostingController(rootView: AnyView(first().environment(\.self, context.environment)))
        let secondHost = NSHostingController(rootView: AnyView(second().environment(\.self, context.environment)))
        let firstItem = NSSplitViewItem(viewController: firstHost)
        firstItem.minimumThickness = minimumFirst
        firstItem.preferredThicknessFraction = initialFraction
        firstItem.holdingPriority = proportionalResize ? .defaultLow : NSLayoutConstraint.Priority(260)
        let secondItem = NSSplitViewItem(viewController: secondHost)
        secondItem.minimumThickness = minimumSecond
        controller.addSplitViewItem(firstItem)
        controller.addSplitViewItem(secondItem)
        if let initialLength,
           UserDefaults.standard.object(forKey: "NSSplitView Subview Frames \(name)") == nil {
            controller.initialDivision = (initialFraction, minimumFirst, minimumSecond, initialLength)
        }
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
