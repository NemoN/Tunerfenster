import SwiftUI

struct TunerStatusSummary: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    @State private var showingUsage = false

    var body: some View {
        HStack(spacing: 4) {
            Text(L10n.text(monitor.tuners.count == 1 ? "tunerCountOne" : "tunerCountMany", String(monitor.tuners.count)))
            Text("·").accessibilityHidden(true)
            Button { showingUsage.toggle() } label: {
                HStack(spacing: 3) {
                    Text(L10n.text("busyTunerCount", String(monitor.busyTunerCount)))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.text("showTunerUsage", String(monitor.busyTunerCount)))
            .help(L10n.text("showTunerUsageHelp"))
            Text("·").accessibilityHidden(true)
            Text(L10n.text(monitor.liveCount == 1 ? "previewCountOne" : "previewCountMany", String(monitor.liveCount)))
            Text("·").accessibilityHidden(true)
            Text(L10n.text(monitor.epgCount == 1 ? "epgScanCountOne" : "epgScanCountMany", String(monitor.epgCount)))
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .popover(isPresented: $showingUsage, arrowEdge: .bottom) {
            TunerUsageView(monitor: monitor) { showingUsage = false }
        }
    }
}

struct TunerUsageView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let close: () -> Void

    var body: some View {
        let usage = monitor.tunerUsage
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("tunerUsageTitle")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("closeUsage"))
            }
            Text(L10n.text("serverTunerUsageHelp")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !monitor.connected {
                Label(L10n.text("usageOffline"), systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(ThemeColors.warning)
            } else if monitor.paused {
                Label(L10n.text("usagePaused"), systemImage: "pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if usage.isEmpty {
                Label(L10n.text("noTunersInUse"), systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(usage) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.tuner.input.shortName).font(.system(size: 13, weight: .semibold))
                                    .help(item.tuner.input.input)
                                ForEach(item.subscriptions) { subscription in
                                    HStack(alignment: .top, spacing: 12) {
                                        Label(subscription.usageKind.title, systemImage: subscription.usageKind.symbol)
                                            .frame(width: 155, alignment: .leading).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(subscription.usageName(for: item.tuner.input))
                                            if let detail = subscription.usageDetail {
                                                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.font(.system(size: 12))
                                }
                                if item.unassignedCount > 0 {
                                    Label(L10n.text("usageUnassigned", String(item.unassignedCount)), systemImage: "questionmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if item.id != usage.last?.id { Divider() }
                        }
                    }.textSelection(.enabled).padding(.trailing, 6)
                }.frame(height: 360)
            }
            if let update = monitor.lastUpdate {
                Text(L10n.text("usageUpdated", L10n.time(update))).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 500).playbackPanel()
    }
}
