import SwiftUI

struct FullScreenPlaybackOverlay<Transport: View>: View {
    @ObservedObject var visibility: PlaybackControlsVisibility
    @EnvironmentObject private var window: PlaybackWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let title: String
    var detail: String? = nil
    var encrypted = false
    @ViewBuilder let transport: () -> Transport

    var body: some View {
        Group {
            if visibility.visible {
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.headline).lineLimit(1)
                            if let detail {
                                HStack(spacing: 6) {
                                    Text(detail).lineLimit(1)
                                    if encrypted {
                                        Image(systemName: "key.horizontal.fill")
                                            .help(L10n.text("encryptedStream")).accessibilityLabel(L10n.text("encryptedStream"))
                                            .accessibilityIdentifier("encryptedStream")
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
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
