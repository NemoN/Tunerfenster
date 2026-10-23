import SwiftUI
import AppKit

/// Keeps both the text and symbol visible in macOS toolbar segments.
struct SymbolSegmentedPicker: NSViewRepresentable {
    struct Option {
        let title: String
        let symbol: String
    }

    let title: String
    let options: [Option]
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.font = .systemFont(ofSize: 12)
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectSegment(_:))
        control.setContentHuggingPriority(.required, for: .vertical)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.segmentCount = options.count
        for (index, option) in options.enumerated() {
            control.setLabel(option.title, forSegment: index)
            control.setImage(NSImage(systemSymbolName: option.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)), forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        control.selectedSegment = selection
        control.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func selectSegment(_ sender: NSSegmentedControl) {
            guard sender.selectedSegment >= 0 else { return }
            selection.wrappedValue = sender.selectedSegment
        }
    }
}
