import AppKit
import SwiftUI

/// Flat vector badges stay crisp at menu size and on Retina displays.
@MainActor
private enum FlagSymbols {
    static let german = make(.german)
    static let british = make(.english)

    private static func make(_ language: AppLanguage) -> NSImage {
        let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            edge.addClip()
            if language == .german {
                NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
                NSRect(x: 0, y: 12, width: 27, height: 6).fill()
                NSColor(calibratedRed: 0.87, green: 0.04, blue: 0.08, alpha: 1).setFill()
                NSRect(x: 0, y: 6, width: 27, height: 6).fill()
                NSColor(calibratedRed: 1, green: 0.81, blue: 0, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 27, height: 6).fill()
            } else {
                NSColor(calibratedRed: 0.04, green: 0.16, blue: 0.38, alpha: 1).setFill()
                bounds.fill()
                let diagonals = NSBezierPath()
                diagonals.move(to: NSPoint(x: -2, y: -1))
                diagonals.line(to: NSPoint(x: 29, y: 19))
                diagonals.move(to: NSPoint(x: -2, y: 19))
                diagonals.line(to: NSPoint(x: 29, y: -1))
                NSColor.white.setStroke()
                diagonals.lineWidth = 5
                diagonals.stroke()
                let red = NSColor(calibratedRed: 0.79, green: 0.06, blue: 0.18, alpha: 1)
                red.setStroke()
                diagonals.lineWidth = 2
                diagonals.stroke()
                NSColor.white.setFill()
                NSRect(x: 10, y: 0, width: 7, height: 18).fill()
                NSRect(x: 0, y: 5.5, width: 27, height: 7).fill()
                red.setFill()
                NSRect(x: 11.5, y: 0, width: 4, height: 18).fill()
                NSRect(x: 0, y: 7, width: 27, height: 4).fill()
            }
            NSColor.white.withAlphaComponent(0.3).setStroke()
            edge.lineWidth = 1
            edge.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct LanguageFlag: View {
    let language: AppLanguage
    var body: some View {
        Image(nsImage: language == .german ? FlagSymbols.german : FlagSymbols.british)
            .renderingMode(.original)
            .accessibilityHidden(true)
    }
}

struct LanguageOption: View {
    let language: AppLanguage
    var body: some View {
        Label { Text(language.name) } icon: { LanguageFlag(language: language) }
    }
}
