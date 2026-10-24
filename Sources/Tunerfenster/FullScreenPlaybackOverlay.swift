import AppKit
import SwiftUI

struct FullScreenPlaybackOverlay<Transport: View>: View {
    @ObservedObject var visibility: PlaybackControlsVisibility
    @EnvironmentObject private var window: PlaybackWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let title: String
    var detail: String? = nil
    @ViewBuilder let transport: () -> Transport

    var body: some View {
        Group {
            if visibility.visible {
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.headline).lineLimit(1)
                            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { window.toggleFullScreen() } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 28, height: 28)
                        }.buttonStyle(.plain).help(L10n.text("exitFullScreen"))
                            .accessibilityLabel(L10n.text("exitFullScreen"))
                    }
                    transport()
                }
                .frame(maxWidth: 980)
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background { VideoControlsBackground(edge: .bottom) }
                .background(FullScreenControlsRegion(controller: window).accessibilityHidden(true))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("playbackControls"))
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visibility.visible)
        .onChange(of: voiceOver, initial: true) { _, value in visibility.useAccessibility(value) }
        .onDisappear { visibility.interact(false) }
    }
}

private struct FullScreenControlsRegion: NSViewRepresentable {
    let controller: PlaybackWindow
    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        controller.controlsView = view
        return view
    }
    func updateNSView(_ nsView: Probe, context: Context) {
        controller.controlsView = nsView
    }
}
