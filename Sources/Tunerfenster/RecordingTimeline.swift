import AppKit
import SwiftUI

/// Retain AppKit's tracking, keyboard and accessibility behavior with a narrow playhead.
struct RecordingTimeline: NSViewRepresentable {
    @Binding var value: Double
    var maximum: Double
    var enabled: Bool
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onEditingEnded: () -> Void

    final class Cell: NSSliderCell {
        override func knobRect(flipped: Bool) -> NSRect {
            let rect = super.knobRect(flipped: flipped)
            let bar = barRect(flipped: flipped)
            return NSRect(x: rect.midX - 4, y: bar.midY - 9, width: 8, height: 18)
        }

        override func drawKnob(_ knobRect: NSRect) {
            (isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor).setFill()
            NSBezierPath(roundedRect: knobRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    final class Control: NSSlider {
        var onEditingEnded: (() -> Void)?
        var onEditingChanged: ((Bool) -> Void)?
        override func mouseDown(with event: NSEvent) {
            let tracking = isEnabled
            if tracking { onEditingChanged?(true) }
            super.mouseDown(with: event)
            if tracking { onEditingEnded?(); onEditingChanged?(false) }
        }
        override func keyDown(with event: NSEvent) {
            super.keyDown(with: event)
            if isEnabled { onEditingEnded?() }
        }
    }

    final class Coordinator: NSObject {
        var parent: RecordingTimeline
        init(_ parent: RecordingTimeline) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = sender.doubleValue }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Control {
        let control = Control()
        control.cell = Cell()
        control.sliderType = .linear
        control.isVertical = false
        control.isContinuous = true
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: Control, context: Context) {
        context.coordinator.parent = self
        control.minValue = 0
        control.maxValue = max(1, maximum)
        control.doubleValue = max(0, min(control.maxValue, value))
        control.isEnabled = enabled
        control.onEditingEnded = onEditingEnded
        control.onEditingChanged = onEditingChanged
        control.setAccessibilityLabel(L10n.text("recordingPosition"))
    }
}
