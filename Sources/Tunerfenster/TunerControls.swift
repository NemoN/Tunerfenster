import SwiftUI

struct ChannelSelectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    let close: () -> Void
    @State private var search = ""
    @State private var allServices = false
    @State private var selectedID: String?
    @State private var revealID: String?
    @AppStorage("lnbSwitchMHz") private var switchMHz = 11700.0

    private var items: [StreamChoice] {
        monitor.choices.filter {
            (allServices || $0.mapped) && $0.matches(input: tuner.input) &&
            (search.isEmpty || "\($0.name) \($0.service.network ?? "") \($0.service.multiplex ?? "")".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        let currentID = monitor.currentChoice(for: tuner)?.id
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("chooseChannelFor", tuner.input.shortName)).font(.headline)
            Button {
                monitor.choose(nil, for: tuner); close()
            } label: {
                Label(L10n.text("automaticFollow"), systemImage: monitor.savedManual[tuner.id] == nil ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
            }.controlSize(.large)
            Text(L10n.text("manualRoutingNote")).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            TextField(L10n.text("searchChannels"), text: $search).textFieldStyle(.roundedBorder)
                .onChange(of: search) { _, _ in selectedID = items.count == 1 ? items.first?.id : nil }
                .onChange(of: allServices) { _, _ in
                    if !items.contains(where: { $0.id == selectedID }) { selectedID = nil }
                }
            Picker(L10n.text("channelCatalog"), selection: $allServices) {
                Text(L10n.text("mappedChannels")).tag(false)
                Text(L10n.text("allServices")).tag(true)
            }.pickerStyle(.segmented)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.text("noMatchingChannels")).font(.headline)
                    Text(L10n.text("noMatchingChannelsHelp")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChannelChoiceList(items: items, selectedID: $selectedID, currentID: currentID,
                                  revealID: revealID, switchMHz: switchMHz, activate: switchChannel)
            }
            HStack {
                Spacer()
                Button(L10n.text("switchChannel")) {
                    guard let item = items.first(where: { $0.id == selectedID }) else { return }
                    switchChannel(item)
                }.keyboardShortcut(.defaultAction)
                    .disabled(!items.contains { $0.id == selectedID })
            }
            Text(L10n.text("manualSessionNote")).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 440, height: 510)
            .playbackPanel()
            .onAppear { restoreCurrentChannel() }
            .onChange(of: monitor.choices.map(\.id)) { _, _ in
                if selectedID == nil && search.isEmpty { restoreCurrentChannel() }
            }
    }

    private func restoreCurrentChannel() {
        guard let current = monitor.currentChoice(for: tuner) else { return }
        allServices = !current.mapped
        selectedID = current.id
        revealID = current.id
    }

    private func switchChannel(_ item: StreamChoice) {
        monitor.choose(item, for: tuner)
        close()
    }
}

struct ReceptionDetailsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    @AppStorage("lnbSwitchMHz") private var switchMHz = 11700.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("receptionDetails")).font(.headline)
            Text(tuner.input.input).font(.callout).textSelection(.enabled)
            if let choice = monitor.manual[tuner.id] {
                Divider()
                Text(L10n.text("manualPreviewName", choice.name)).font(.subheadline.weight(.semibold))
                Text(L10n.text("previewVia", sourceNames)).font(.callout).foregroundStyle(.secondary)
                muxRows(choice.multiplex)
                Text(L10n.text("manualRoutingNote")).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text(L10n.text("physicalReception")).font(.subheadline.weight(.semibold))
            muxRows(monitor.physicalMultiplex(for: tuner))
            if let stream = tuner.input.stream {
                if monitor.physicalMultiplex(for: tuner) == nil { Text(stream).font(.callout).textSelection(.enabled) }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    row("signal", tuner.input.signalLabel)
                    if let snr = tuner.input.snrLabel { row("snr", snr) }
                    row("dataRate", L10n.text("bitrate", L10n.decimal((tuner.input.bps ?? 0) / 1_000_000)))
                    row("continuityErrors", String(tuner.input.cc ?? 0))
                }.font(.callout).monospacedDigit()
            }
            Text(L10n.text("bandCalculation", Multiplex.number(switchMHz))).font(.caption).foregroundStyle(.secondary)
            if let warning = monitor.receptionWarning { Text(warning.localizedDescription).font(.caption).foregroundStyle(ThemeColors.warning) }
        }.padding(18).frame(width: 380).playbackPanel()
    }

    private var sourceNames: String {
        let sources = monitor.sources(for: tuner)
        return sources.isEmpty ? L10n.text("tunerPending") : sources.map(\.shortName).joined(separator: ", ")
    }

    @ViewBuilder private func muxRows(_ mux: Multiplex?) -> some View {
        if let mux {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                if let value = mux.network { row("network", value) }
                if let value = mux.frequencyLabel { row("frequency", value) }
                if mux.isSatellite, let value = mux.polarisation { row("polarisation", value) }
                if let value = mux.band(switchMHz: switchMHz) { row("band", value) }
                if let value = mux.delsys { row("deliverySystem", value) }
                if let value = mux.modulation { row("modulation", value) }
                if let value = mux.symbolrate, value > 0 { row("symbolRate", "\(Multiplex.number(value / 1000)) kSym/s") }
                if let value = mux.fec { row("fec", value) }
                if let value = mux.orbital { row("orbitalPosition", value) }
            }.font(.callout).monospacedDigit().textSelection(.enabled)
        } else {
            Text(L10n.text("noReceptionData")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.text(key)).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FocusedReceptionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    @AppStorage("lnbSwitchMHz") private var switchMHz = 11700.0
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("receptionDetails")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button { showingDetails = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("receptionFor", tuner.input.shortName))
                    .help(L10n.text("receptionDetails"))
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        ReceptionDetailsView(monitor: monitor, tuner: tuner)
                    }
            }
            if monitor.manual[tuner.id] != nil {
                Text(L10n.text("previewVia", sourceNames)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(monitor.displayedMultiplex(for: tuner)?.summary(switchMHz: switchMHz) ??
                 (monitor.manual[tuner.id] == nil ? tuner.input.stream : nil) ?? L10n.text("noActiveMultiplex"))
                .font(.caption.weight(.medium)).monospacedDigit().textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let input = source, input.stream != nil {
                HStack {
                    Text(input.signalLabel)
                    Spacer(minLength: 8)
                    if let snr = input.snrLabel { Text(snr) }
                }
                HStack {
                    Text(L10n.text("bitrate", L10n.decimal((input.bps ?? 0) / 1_000_000)))
                    Spacer(minLength: 8)
                    Text(L10n.text("continuityErrorCount", input.cc.map(String.init) ?? "–"))
                }
            } else {
                Text(L10n.text(monitor.manual[tuner.id] == nil ? "waitingChannel" : "tunerPending"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption).monospacedDigit()
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var sourceNames: String {
        let sources = monitor.sources(for: tuner)
        return sources.isEmpty ? L10n.text("tunerPending") : sources.map(\.shortName).joined(separator: ", ")
    }

    private var source: Input? {
        let inputs = monitor.sources(for: tuner)
        return inputs.count == 1 ? inputs.first : nil
    }
}
