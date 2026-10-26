import SwiftUI

struct RecordingTransportView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var playback: Playback
    @ObservedObject private var preferences: CommercialPreferences
    let item: SavedRecording
    var fullScreen = false
    var onEditingChanged: (Bool) -> Void = { _ in }

    init(library: RecordingLibrary, playback: Playback, item: SavedRecording,
         fullScreen: Bool = false, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.library = library; self.playback = playback; self.item = item
        self.fullScreen = fullScreen; self.onEditingChanged = onEditingChanged
        preferences = library.commercialPreferences
    }

    var body: some View {
        let needsStart = !library.playbackRequested
        let replay = playback.ended || playback.failed || library.playbackError != nil
        let position = needsStart || playback.restoringPosition ? Double(library.progress(for: item).position) : playback.positionSeconds
        let hasDuration = !needsStart && playback.durationSeconds > 0
        let duration = hasDuration ? playback.durationSeconds : library.commercialFileDuration ?? item.recordedDuration
        let estimated = hasDuration ? playback.timelineEstimated : duration > 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await library.play(item, fromBeginning: true) } } label: {
                    Image(systemName: "backward.end.fill").frame(width: 28, height: 28)
                }.help(L10n.text("recordingPlayFromBeginning"))
                    .accessibilityLabel(L10n.text("recordingPlayFromBeginning"))
                    .disabled(library.opening || !item.canPlay)
                Button { library.togglePause() } label: {
                    Image(systemName: needsStart ? "play.fill" : replay ? "arrow.counterclockwise" : playback.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                }.help(L10n.text(needsStart ? "recordingStartPlayback" : replay ? "replayRecording" : "recordingTogglePause"))
                    .accessibilityLabel(L10n.text(needsStart ? "recordingStartPlayback" : replay ? "replayRecording" : playback.isPaused ? "resumeRecording" : "pauseRecording"))
                    .accessibilityIdentifier("recordingPlaybackToggle")
                    .disabled(library.opening || !item.canPlay)
                Text(Self.time(position)).monospacedDigit().font(.caption)
                RecordingTimeline(value: Binding(get: { position }, set: { library.seekPlayback(to: $0) }),
                                  maximum: max(duration, position, 1), enabled: !needsStart && playback.canSeek,
                                  commercialBreaks: library.commercialBreaks,
                                  onEditingChanged: { editing in library.setTimelineEditing(editing); onEditingChanged(editing) },
                                  onEditingEnded: { library.savePlaybackPosition() })
                    .frame(height: 24)
                Text((estimated ? "≈ " : "") + Self.time(duration)).monospacedDigit().font(.caption)
                    .help(L10n.text(estimated ? "estimatedRecordingDuration" : "recordingDuration"))
                Button { library.toggleMute() } label: {
                    Image(systemName: library.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 28, height: 28)
                }.help(L10n.text(library.muted ? "unmuteHelp" : "muteHelp"))
                    .accessibilityLabel(L10n.text("recordingAudio"))
                    .accessibilityValue(L10n.text(library.muted ? "audioMuted" : "audioOn"))
                    .disabled(needsStart)
            }
            .buttonStyle(.plain)
            .font(fullScreen ? .title3 : .body)
        }
        .onChange(of: preferences.host) { _, _ in library.loadCommercials(force: true) }
        .onChange(of: preferences.port) { _, _ in library.loadCommercials(force: true) }
    }

    private static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) :
            String(format: "%d:%02d", value / 60, value % 60)
    }
}
