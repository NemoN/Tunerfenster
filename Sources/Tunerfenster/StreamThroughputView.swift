import SwiftUI

/// VLC's input byte counters represent stream payload, not network overhead.
struct StreamThroughputSampler {
    private var previous: [UUID: UInt32] = [:]
    private var previousTime: TimeInterval?

    mutating func update(_ counters: [UUID: UInt32], at time: TimeInterval) -> Double {
        defer { previous = counters; previousTime = time }
        guard let previousTime, time > previousTime else { return 0 }
        let elapsed = time - previousTime
        let bytes = counters.reduce(0.0) { total, entry in
            guard let old = previous[entry.key] else { return total }
            return total + Double(entry.value &- old)
        }
        return bytes * 8 / elapsed / 1_000_000
    }
}

struct StreamThroughputView: View {
    @ObservedObject var fleet: ServerFleet
    @State private var sampler = StreamThroughputSampler()
    @State private var megabitsPerSecond = 0.0

    var body: some View {
        Text(L10n.text("streamThroughput", L10n.decimal(megabitsPerSecond)))
            .lineLimit(1)
            .fixedSize()
            .help(L10n.text("streamThroughputHelp"))
            .task {
                while !Task.isCancelled {
                    var counters = [UUID: UInt32]()
                    for node in fleet.nodes {
                        for player in node.monitor.streamPlayers {
                            let revision = player.streamRevision
                            if let stats = await player.statisticsSnapshot(), player.streamRevision == revision {
                                counters[revision] = stats.readBytes
                            }
                        }
                    }
                    guard !Task.isCancelled else { return }
                    megabitsPerSecond = sampler.update(counters, at: ProcessInfo.processInfo.systemUptime)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
    }
}
