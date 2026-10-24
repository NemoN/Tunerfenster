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

struct DetailPanelBackground: View {
    var cornerRadius: CGFloat = 8
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                if contrast != .increased && !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(stops: [
                            .init(color: .white.opacity(colorScheme == .dark ? 0.04 : 0.02), location: 0),
                            .init(color: .clear, location: 0.55),
                            .init(color: .black.opacity(0.025), location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DetailsHandleBackground: View {
    let sideBySide: Bool
    let highlighted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule().fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                if contrast == .increased || reduceTransparency {
                    Capsule().fill(Color.primary.opacity(highlighted ? 0.12 : 0.06))
                } else {
                    Capsule().fill(LinearGradient(stops: [
                        .init(color: .white.opacity(colorScheme == .dark ? (highlighted ? 0.14 : 0.07) : 0.03), location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(highlighted ? 0.08 : 0.04), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .padding(sideBySide ? .horizontal : .vertical, 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct VideoControlsBackground: View {
    let edge: VerticalEdge
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if contrast == .increased || reduceTransparency {
                Color.black
            } else {
                // The fade extends into the picture; the area directly behind
                // labels stays dark enough even over a white video frame.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.78), location: 0.42),
                    .init(color: .black.opacity(0.90), location: 1)
                ], startPoint: edge == .bottom ? .top : .bottom,
                   endPoint: edge == .bottom ? .bottom : .top)
                .padding(edge == .bottom ? .top : .bottom, -24)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum ThemeColors {
    static let detailSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        var color = NSColor.secondaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
        }
        return color.withAlphaComponent(max(color.alphaComponent, 0.6))
    })

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
