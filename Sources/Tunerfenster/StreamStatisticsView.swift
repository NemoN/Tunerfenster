import SwiftUI

struct StreamStatisticsOverlay: View {
    @ObservedObject var playback: Playback
    let close: () -> Void
    @State private var snapshot: StreamStatistics?

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.text("streamStatistics"), systemImage: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 8)
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help(L10n.text("hideStreamStatistics"))
                        .accessibilityLabel(L10n.text("hideStreamStatistics"))
                }
                ScrollView {
                    if let stats = snapshot {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                            if stats.width > 0 {
                                row("statsResolution", "\(stats.width) × \(stats.height)")
                            }
                            row("statsInputRead", "\(L10n.decimal(Double(stats.readBytes) / 1_000_000)) MB")
                            row("statsInputRate", "\(L10n.decimal(stats.inputMbps)) Mbit/s")
                            row("statsDemuxRead", "\(L10n.decimal(Double(stats.demuxBytes) / 1_000_000)) MB")
                            row("statsDemuxRate", "\(L10n.decimal(stats.demuxMbps)) Mbit/s")
                            row("statsCorrupted", String(stats.corrupted))
                            row("statsDiscontinuities", String(stats.discontinuities))
                            separator
                            row("statsVideoDecoded", String(stats.decodedVideo))
                            row("statsVideoDisplayed", String(stats.displayedPictures))
                            row("statsVideoLost", String(stats.lostPictures))
                            separator
                            row("statsAudioDecoded", String(stats.decodedAudio))
                            row("statsAudioPlayed", String(stats.playedAudioBuffers))
                            row("statsAudioLost", String(stats.lostAudioBuffers))
                        }
                        .font(.system(size: 11)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(L10n.text("statsWaiting"))
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(L10n.text("statsRefresh"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
            .frame(width: min(350, geometry.size.width), height: min(350, geometry.size.height), alignment: .top)
            .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
        }
        .task(id: playback.streamRevision) {
            snapshot = nil
            while !Task.isCancelled {
                let value = await playback.statisticsSnapshot()
                guard !Task.isCancelled else { return }
                snapshot = value
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.text(key)).foregroundStyle(.white.opacity(0.8))
            Text(value).gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Divider().overlay(.white.opacity(0.2)).padding(.vertical, 3)
    }
}
