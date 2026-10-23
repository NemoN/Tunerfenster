import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let preferenceKey = "appAppearance"
    var id: String { rawValue }
    var title: String { L10n.text("appearance" + rawValue.capitalized) }
    var next: AppAppearance {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct AppearanceButton: View {
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system
    @ObservedObject private var language = LanguageStore.shared

    var body: some View {
        Button {
            appearance = appearance.next
        } label: {
            Label(L10n.text("appearance"), systemImage: appearance.symbol)
        }
        .labelStyle(.iconOnly)
        .help(L10n.text("appearanceCycle", appearance.title, appearance.next.title))
        .accessibilityLabel(L10n.text("appearance"))
        .accessibilityValue(appearance.title)
    }
}

enum ThemeColors {
    static let recording = Color(red: 0.70, green: 0.06, blue: 0.09)
    static let recordingPulse = Color(red: 0.55, green: 0.03, blue: 0.05)
    static let active = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemGreen :
            NSColor(calibratedRed: 0.06, green: 0.40, blue: 0.18, alpha: 1)
    })

    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange :
            NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.00, alpha: 1)
    })
}
