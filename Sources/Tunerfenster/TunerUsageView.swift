import SwiftUI

struct TunerStatusSummary: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    @ObservedObject var fleet: ServerFleet
    var perServer = false
    @State private var showingUsage = false

    var body: some View {
        let monitors = perServer ? [monitor] : fleet.nodes.map(\.monitor)
        let tunerCount = monitors.reduce(0) { $0 + $1.tuners.count }
        let busyCount = monitors.reduce(0) { $0 + $1.busyTunerCount }
        let liveCount = monitors.reduce(0) { $0 + $1.liveCount }
        let epgCount = monitors.reduce(0) { $0 + $1.epgCount }
        HStack(spacing: 4) {
            Text(L10n.text(tunerCount == 1 ? "tunerCountOne" : "tunerCountMany", String(tunerCount)))
            Text("·").accessibilityHidden(true)
            Button { showingUsage.toggle() } label: {
                HStack(spacing: 3) {
                    Text(L10n.text("busyTunerCount", String(busyCount)))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.text("showTunerUsage", String(busyCount)))
            .help(L10n.text("showTunerUsageHelp"))
            Text("·").accessibilityHidden(true)
            Text(L10n.text(liveCount == 1 ? "previewCountOne" : "previewCountMany", String(liveCount)))
            Text("·").accessibilityHidden(true)
            Text(L10n.text(epgCount == 1 ? "epgScanCountOne" : "epgScanCountMany", String(epgCount)))
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .popover(isPresented: $showingUsage, arrowEdge: .bottom) {
            if fleet.hasMultipleServers && !perServer {
                FleetTunerUsageView(fleet: fleet) { showingUsage = false }
            } else {
                TunerUsageView(monitor: monitor) { showingUsage = false }
            }
        }
    }
}

private struct FleetTunerUsageView: View {
    @ObservedObject var fleet: ServerFleet
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("tunerUsageTitle")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("closeUsage"))
            }
            Text(L10n.text("serverTunerUsageHelp")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(fleet.nodes) { node in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(node.profile.label).font(.headline)
                            if !node.monitor.connected {
                                Label(L10n.text("usageOffline"), systemImage: "wifi.slash").foregroundStyle(ThemeColors.warning)
                            } else if node.monitor.tunerUsage.isEmpty {
                                Label(L10n.text("noTunersInUse"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                            } else {
                                ForEach(node.monitor.tunerUsage) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.tuner.input.shortName).font(.subheadline.weight(.semibold))
                                        ForEach(item.subscriptions) { subscription in
                                            HStack(alignment: .top, spacing: 12) {
                                                Label(subscription.usageKind.title, systemImage: subscription.usageKind.symbol)
                                                    .frame(width: 155, alignment: .leading).foregroundStyle(.secondary)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(subscription.usageName(for: item.tuner.input))
                                                    if let detail = subscription.usageDetail { Text(detail).foregroundStyle(.secondary) }
                                                }
                                            }
                                        }
                                        if item.unassignedCount > 0 {
                                            Label(L10n.text("usageUnassigned", String(item.unassignedCount)), systemImage: "questionmark.circle")
                                        }
                                    }.font(.caption)
                                }
                            }
                        }
                        if node.id != fleet.nodes.last?.id { Divider() }
                    }
                }.textSelection(.enabled)
            }.frame(height: 360)
        }.padding(18).frame(width: 500).playbackPanel()
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
