import SwiftUI

struct RecordingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var library: RecordingLibrary
    @State private var search = ""
    private var filtered: [SavedRecording] { library.items.filter { $0.matches(search) } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("recordingsMode")).font(.headline)
                    Spacer()
                    if library.loading { ProgressView().controlSize(.small) }
                    Text(String(library.items.count)).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.horizontal, 12).padding(.top, 12)
                TextField(L10n.text("searchRecordings"), text: $search)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                if let error = library.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(ThemeColors.warning).font(.callout)
                        Button(L10n.text("retryRecordings")) { Task { await library.refresh() } }.disabled(library.loading)
                    }.padding(.horizontal, 12)
                }
                if (!library.configured || library.loading) && library.items.isEmpty {
                    empty("loadingRecordings", symbol: "rectangle.stack")
                } else if filtered.isEmpty {
                    empty(search.isEmpty ? "noRecordings" : "noMatchingRecordings", symbol: "rectangle.stack")
                } else {
                    List(selection: Binding<String?>(get: { library.selected?.id }, set: { id in
                        guard let item = library.items.first(where: { $0.id == id }) else { return }
                        Task { await library.play(item) }
                    })) {
                        ForEach(filtered) { item in
                            row(item).tag(item.id)
                        }
                    }.listStyle(.inset).accessibilityLabel(L10n.text("recordingsMode"))
                }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
            .background(Color(nsColor: .controlBackgroundColor))
            RecordingPlayerView(library: library, playback: library.playback)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ item: SavedRecording) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Spacer(minLength: 2)
                Image(systemName: item.canPlay ? "play.circle" : "exclamationmark.circle")
            }
            if let channel = item.channelname { Text(channel).lineLimit(1) }
            if let date = item.dateLabel { Text(date).lineLimit(1) }
            Label(item.statusLabel, systemImage: item.isRunning ? "record.circle" : item.canPlay ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(item.isRunning ? ThemeColors.recording : item.hasError || !item.canPlay ? ThemeColors.warning : .secondary)
        }
        .font(.caption).padding(.vertical, 5)
        .help(item.canPlay ? L10n.text("playRecording", item.name) : L10n.text("recordingFileUnavailable"))
        .accessibilityElement(children: .combine)
    }

    private func empty(_ key: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2)
            Text(L10n.text(key)).multilineTextAlignment(.center).font(.callout)
        }.foregroundStyle(.secondary).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecordingPlayerView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var playback: Playback
    private var needsReplay: Bool { playback.ended || playback.failed || library.playbackError != nil }
    private var playerMessage: String {
        if let error = library.playbackError { return error.localizedDescription }
        if playback.ended { return L10n.text("recordingPlaybackEnded") }
        if playback.failed { return L10n.text("recordingPlaybackInterrupted") }
        return playback.status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = library.selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline).lineLimit(2)
                    Text([item.channelname, item.dateLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12)
                ZStack {
                    Color.black
                    VideoSurface(playback: playback)
                    if library.opening || !playback.isPlaying && !playback.isPaused {
                        VStack(spacing: 8) {
                            if library.opening { ProgressView().controlSize(.small) }
                            Text(playerMessage)
                                .font(.callout).multilineTextAlignment(.center)
                        }.padding(20).foregroundStyle(.white)
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                HStack(spacing: 12) {
                    Button { library.togglePause() } label: {
                        Image(systemName: needsReplay ? "arrow.counterclockwise" : playback.isPaused ? "play.fill" : "pause.fill")
                    }.help(L10n.text(needsReplay ? "replayRecording" : "recordingTogglePause"))
                        .accessibilityLabel(L10n.text(needsReplay ? "replayRecording" : playback.isPaused ? "resumeRecording" : "pauseRecording"))
                        .disabled(library.opening)
                    Text(Self.time(playback.positionSeconds)).monospacedDigit().font(.caption)
                    Slider(value: Binding(get: { playback.positionSeconds }, set: { playback.seek(to: $0) }),
                           in: 0...max(playback.durationSeconds, playback.positionSeconds, 1))
                        .disabled(!playback.canSeek).accessibilityLabel(L10n.text("recordingPosition"))
                    Text((playback.timelineEstimated ? "≈ " : "") + Self.time(playback.durationSeconds)).monospacedDigit().font(.caption)
                        .help(L10n.text(playback.timelineEstimated ? "estimatedRecordingDuration" : "recordingDuration"))
                    Button { library.toggleMute() } label: {
                        Image(systemName: library.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }.help(L10n.text(library.muted ? "unmuteHelp" : "muteHelp"))
                        .accessibilityLabel(L10n.text("recordingAudio"))
                        .accessibilityValue(L10n.text(library.muted ? "audioMuted" : "audioOn"))
                }.padding(12)
                if item.subtitleText != nil || item.detail != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if let subtitle = item.subtitleText { Text(subtitle).fontWeight(.medium) }
                            if let detail = item.detail { Text(detail).textSelection(.enabled) }
                        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(maxHeight: 110)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle").font(.system(size: 36, weight: .light))
                    Text(L10n.text("selectRecording")).font(.headline)
                    Text(library.playbackError?.localizedDescription ?? L10n.text("selectRecordingHelp"))
                        .font(.callout).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) :
            String(format: "%d:%02d", value / 60, value % 60)
    }
}
