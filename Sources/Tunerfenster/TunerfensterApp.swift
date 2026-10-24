import SwiftUI
import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var monitor: Monitor?
    weak var updater: UpdateChecker?
    private var terminating = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let monitor else { return .terminateNow }
        if !terminating {
            terminating = true
            Task {
                await monitor.recordings.prepareForTermination()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { monitor?.shutdown() }
    func applicationDidBecomeActive(_ notification: Notification) {
        LanguageStore.shared.localizeNativeMenus()
        Task { await updater?.check(automatically: true) }
    }
}

@main
struct TunerfensterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor()
    @StateObject private var updater = UpdateChecker()
    @ObservedObject private var language = LanguageStore.shared
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system
    @Environment(\.openWindow) private var openWindow
    @State private var settingsVisible = false

    init() {
        // Release verification runs the exact signed executable under its hardened
        // runtime, without opening streams or reading the TVHeadend password.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--check-vlc") || arguments.contains("--check-playback") {
            switch VLC.shared {
            case .success(let api):
                print("Bundled VLC \(api.version) loaded from \(api.libraryURL.path).")
                if let index = arguments.firstIndex(of: "--check-playback") {
                    guard index + 1 < arguments.count else {
                        fputs("Usage: --check-playback /path/to/test.ts\n", stderr)
                        exit(EXIT_FAILURE)
                    }
                    do { try PlaybackCheck.run(api: api, file: URL(fileURLWithPath: arguments[index + 1])) }
                    catch { fputs("Playback check failed: \(error.localizedDescription)\n", stderr); exit(EXIT_FAILURE) }
                }
                exit(EXIT_SUCCESS)
            case .failure(let error):
                fputs("VLC playback engine could not load: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
    }

    var body: some Scene {
        Window("Tunerfenster \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", id: "main") {
            MonitorView(monitor: monitor, recordings: monitor.recordings, updater: updater, settingsVisible: $settingsVisible)
                .environment(\.locale, language.language.locale)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 700, minHeight: 460)
                .onAppear { appearance.apply(); delegate.monitor = monitor; delegate.updater = updater; monitor.start() }
                .onChange(of: appearance) { _, value in value.apply() }
                .task { await updater.runAutomaticChecks() }
                .sheet(isPresented: $settingsVisible) { ConnectionView(monitor: monitor, updater: updater) }
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("settingsMenu")) { settingsVisible = true }.keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.text("checkForUpdates")) {
                    openWindow(id: "updates")
                    Task { await updater.check() }
                }.disabled(updater.isChecking)
            }
            CommandMenu(L10n.text("playbackMenu")) {
                Button(monitor.viewingMode == .recordings ? L10n.text("recordingTogglePause") : monitor.paused ? L10n.text("resume") : L10n.text("pauseAll")) {
                    if monitor.viewingMode == .recordings { monitor.recordings.togglePause() } else { monitor.togglePause() }
                }.keyboardShortcut("p")
                Button(L10n.text("refresh")) { Task {
                    if monitor.viewingMode == .recordings { await monitor.recordings.refresh() }
                    else { await monitor.refresh(reloadCatalog: true) }
                } }.keyboardShortcut("r")
                Divider()
                Button(L10n.text("followAll")) { monitor.followAll() }.disabled(monitor.savedManual.isEmpty)
            }
            CommandMenu(L10n.text("viewingMode")) {
                Button(L10n.text("mosaicMode")) { monitor.setViewingMode(.mosaic) }.keyboardShortcut("1")
                Button(L10n.text("tvMode")) { monitor.setViewingMode(.tv) }.keyboardShortcut("2")
                Button(L10n.text("recordingsMode")) { monitor.setViewingMode(.recordings) }.keyboardShortcut("3")
            }
            CommandMenu(L10n.text("language")) {
                Picker(L10n.text("language"), selection: $language.language) {
                    ForEach(AppLanguage.allCases) { option in LanguageOption(language: option).tag(option) }
                }
            }
        }
        Window(L10n.text("softwareUpdates"), id: "updates") {
            UpdateView(updater: updater)
                .environment(\.locale, language.language.locale)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
    }
}

private struct MonitorView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    @ObservedObject var recordings: RecordingLibrary
    @ObservedObject var updater: UpdateChecker
    @Binding var settingsVisible: Bool
    @AppStorage("onlyBusy") private var onlyBusy = false
    @AppStorage("preferredColumns") private var columns = 0
    private var focusedID: String? { monitor.focusedID }
    @State private var availableSize = CGSize(width: 1280, height: 700)
    @State private var choosingTVChannel = false
    @StateObject private var playbackWindow = PlaybackWindow()
    private var videoOnly: Bool { playbackWindow.fullScreen && (focusedID != nil || monitor.viewingMode == .recordings && recordings.selected != nil && recordings.playbackRequested) }
    private var fullScreenVideo: NSView? {
        if monitor.viewingMode == .recordings {
            return recordings.playbackRequested ? recordings.playback.canvas : nil
        }
        return focusedID.map { monitor.player(for: $0).canvas }
    }

    private var visible: [Tuner] {
        if let focusedID { return monitor.tuners.filter { $0.id == focusedID } }
        return monitor.tuners.filter { tuner in
            let physical = monitor.headerTuner(for: tuner)
            return !onlyBusy || monitor.preview(for: tuner) != nil || physical.hasOwnPreview || physical.hasEPG || physical.unresolvedTV || !physical.previews.isEmpty
        }
    }

    var body: some View {
        Group {
            if videoOnly, monitor.viewingMode == .recordings {
                ZStack { Color.black; VideoSurface(playback: recordings.playback) }
                    .overlay(alignment: .bottom) {
                        if let item = recordings.selected {
                            FullScreenPlaybackOverlay(visibility: playbackWindow.controls, title: item.name, detail: item.channelname) {
                                RecordingTransportView(library: recordings, playback: recordings.playback, item: item,
                                                       fullScreen: true, onEditingChanged: { playbackWindow.controls.interact($0) })
                            }
                        }
                    }.ignoresSafeArea()
            } else if videoOnly, let focusedID, let tuner = monitor.tuners.first(where: { $0.id == focusedID }) {
                ZStack {
                    Color.black
                    VideoSurface(playback: monitor.player(for: focusedID))
                }.overlay(alignment: .bottom) {
                    FullScreenPlaybackOverlay(visibility: playbackWindow.controls,
                                              title: monitor.preview(for: tuner)?.title ?? tuner.input.shortName,
                                              detail: monitor.headerTuner(for: tuner).input.shortName) {
                        HStack(spacing: 14) {
                            Button { monitor.switchFocusedChannel(direction: -1) } label: {
                                Image(systemName: "chevron.up").frame(width: 28, height: 28)
                            }.help(L10n.text("previousChannelHelp")).accessibilityLabel(L10n.text("previousChannel"))
                            Button { monitor.switchFocusedChannel(direction: 1) } label: {
                                Image(systemName: "chevron.down").frame(width: 28, height: 28)
                            }.help(L10n.text("nextChannelHelp")).accessibilityLabel(L10n.text("nextChannel"))
                            Spacer()
                            Button { monitor.toggleAudio(tuner.id) } label: {
                                Image(systemName: monitor.audioID == tuner.id ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .frame(width: 28, height: 28)
                            }.help(L10n.text(monitor.audioID == tuner.id ? "muteHelp" : "unmuteHelp"))
                                .accessibilityLabel(L10n.text("audioForChannel", monitor.preview(for: tuner)?.title ?? tuner.input.shortName))
                                .accessibilityValue(L10n.text(monitor.audioID == tuner.id ? "audioOn" : "audioMuted"))
                        }.buttonStyle(.plain).font(.title3)
                    }
                }.ignoresSafeArea()
            } else {
                monitorContent
            }
        }
        .background(PlaybackWindowBridge(controller: playbackWindow, focused: focusedID != nil,
                                         blocked: settingsVisible || choosingTVChannel,
                                         leaveZoom: { monitor.setViewingMode(.mosaic) },
                                         switchChannel: { monitor.switchFocusedChannel(direction: $0) },
                                         toggleMute: { monitor.toggleMute() }, videoView: fullScreenVideo))
        .toolbar(videoOnly ? .hidden : .automatic, for: .windowToolbar)
        .environmentObject(playbackWindow)
        .task(id: monitor.viewingMode) {
            guard monitor.viewingMode == .recordings else { return }
            var ticks = 0
            while !Task.isCancelled {
                await recordings.updatePlayback()
                if ticks % 30 == 0 { await recordings.refresh() }
                ticks += 1
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private var monitorContent: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    serverStatus.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    if monitor.viewingMode != .recordings { channelControls.fixedSize(horizontal: true, vertical: false) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    serverStatus
                    if monitor.viewingMode != .recordings { channelControls }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 10)

            if monitor.canSelectFocusedTuner, let tuner = monitor.tuners.first(where: { $0.id == focusedID }) {
                HStack(spacing: 12) {
                    Picker(L10n.text("tvTuner"), selection: Binding(get: { tuner.id }, set: { monitor.selectFocusedTuner($0) })) {
                        ForEach(monitor.tuners) { item in Text(monitor.headerTuner(for: item).input.shortName).tag(item.id) }
                    }.frame(maxWidth: 330).help(L10n.text("tvTunerHelp"))
                    Spacer(minLength: 0)
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }

            if monitor.viewingMode != .recordings, let error = monitor.error {
                notice(error.localizedDescription, symbol: "exclamationmark.triangle", color: ThemeColors.warning)
            } else if monitor.viewingMode != .recordings, let warning = monitor.catalogWarning {
                notice(warning.localizedDescription, symbol: "exclamationmark.triangle", color: ThemeColors.warning)
            }
            UpdateBanner(updater: updater)
            if let allocation = monitor.tunerAllocation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: monitor.busyTunerCount >= allocation.targetCount ? "checkmark.circle" : "info.circle")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("allocationOccupancy", String(monitor.busyTunerCount), String(allocation.targetCount)))
                            .font(.callout.weight(.medium))
                        Text(L10n.text("allocationDetails", String(allocation.assignments.count)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { monitor.dismissTunerAllocation() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel(L10n.text("dismissAllocation"))
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }

            GeometryReader { geometry in
                Group {
                if monitor.viewingMode == .recordings {
                    RecordingsView(library: recordings)
                } else if monitor.loading && monitor.tuners.isEmpty {
                    placeholder(title: L10n.text("connectingServer"), detail: L10n.text("loadingTuners"), symbol: "antenna.radiowaves.left.and.right", loading: true)
                } else if monitor.tuners.isEmpty {
                    placeholder(title: monitor.error == nil ? L10n.text("noTuners") : L10n.text("connectionUnavailable"), detail: L10n.text("checkSettings"), symbol: "antenna.radiowaves.left.and.right.slash", loading: false)
                } else if visible.isEmpty {
                    placeholder(title: L10n.text("allIdle"), detail: L10n.text("allIdleDetail"), symbol: "tv", loading: false)
                } else if let focusedID, let tuner = visible.first(where: { $0.id == focusedID }) {
                    FocusedTunerView(monitor: monitor, tuner: tuner, tile: AnyView(
                        TunerTile(tuner: tuner, monitor: monitor, playback: monitor.player(for: tuner.id), focused: true) {
                            monitor.setViewingMode(.mosaic)
                        }
                    ))
                } else {
                    let fit = GridFit.calculate(count: visible.count, width: geometry.size.width, height: geometry.size.height, preferredColumns: focusedID == nil ? columns : 1)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.width), spacing: 10), count: fit.columns), alignment: .center, spacing: 10) {
                        ForEach(visible) { tuner in
                            TunerTile(tuner: tuner, monitor: monitor, playback: monitor.player(for: tuner.id), focused: focusedID == tuner.id) {
                                monitor.focus(tuner.id)
                            }
                            .frame(width: fit.width, height: fit.height)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
                }
                .onAppear { availableSize = geometry.size }
                .onChange(of: geometry.size) { _, size in
                    availableSize = size
                    if focusedID == nil && columns > 0 && !GridFit.canFit(count: visible.count, width: size.width, height: size.height, columns: columns) {
                        columns = 0
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)

            HStack(spacing: 6) {
                Text(monitor.viewingMode == .recordings ? L10n.text("recordingsModeStatus") : monitor.paused ? L10n.text("previewsStopped") : monitor.viewingMode == .tv ? L10n.text("tvModeStatus") : monitor.manual.isEmpty ? L10n.text("followingChannels") : L10n.text("manualPreviewCount", String(monitor.manual.count)))
                Spacer()
                if let update = monitor.lastUpdate {
                    Text(L10n.text("updatedAt", L10n.time(update)))
                }
                PollingIntervalMenu(monitor: monitor)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 18).frame(height: 26)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SymbolSegmentedPicker(title: L10n.text("viewingMode"),
                                      options: ViewingMode.allCases.map { .init(title: $0.title, symbol: $0.symbol) },
                                      selection: Binding(get: { ViewingMode.allCases.firstIndex(of: monitor.viewingMode) ?? 0 }, set: { index in
                                          guard ViewingMode.allCases.indices.contains(index) else { return }
                                          monitor.setViewingMode(ViewingMode.allCases[index])
                                      }))
                    .frame(width: 300).help(L10n.text("viewingModeHelp"))
                if monitor.viewingMode == .mosaic {
                    SymbolSegmentedPicker(title: L10n.text("showTuners"),
                                          options: [.init(title: L10n.text("all"), symbol: "rectangle.stack"),
                                                    .init(title: L10n.text("busy"), symbol: "antenna.radiowaves.left.and.right")],
                                          selection: Binding(get: { onlyBusy ? 1 : 0 }, set: { onlyBusy = $0 == 1 }))
                        .frame(width: 160).help(L10n.text("filterHelp"))
                }
                Menu {
                    Picker(L10n.text("language"), selection: $language.language) {
                        ForEach(AppLanguage.allCases) { option in LanguageOption(language: option).tag(option) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        LanguageFlag(language: language.language)
                        Text(language.language.rawValue.uppercased())
                    }
                }
                    .help(L10n.text("language")).accessibilityLabel(L10n.text("language"))
                    .accessibilityValue(language.language.name)
                if monitor.viewingMode == .mosaic { Menu {
                    Picker(L10n.text("columns"), selection: $columns) {
                        Text(L10n.text("autoFit")).tag(0)
                        ForEach(1...6, id: \.self) { count in
                            Text(count == 1 ? L10n.text("oneColumn") : L10n.text("columnCount", String(count))).tag(count)
                                .disabled(!GridFit.canFit(count: visible.count, width: availableSize.width, height: availableSize.height, columns: count))
                        }
                    }
                } label: { Label(L10n.text("grid"), systemImage: "rectangle.split.3x3") }.help(L10n.text("gridHelp")) }
                if monitor.viewingMode != .recordings { Button { monitor.togglePause() } label: {
                    Label(monitor.paused ? L10n.text("resume") : L10n.text("pause"), systemImage: monitor.paused ? "play.fill" : "pause.fill")
                }.help(monitor.paused ? L10n.text("resumeHelp") : L10n.text("pauseHelp")) }
                Button { Task {
                    if monitor.viewingMode == .recordings { await recordings.refresh() }
                    else { await monitor.refresh(reloadCatalog: true) }
                } } label: { Label(L10n.text("refresh"), systemImage: "arrow.clockwise") }
                    .help(L10n.text(monitor.viewingMode == .recordings ? "refreshRecordings" : "refreshHelp"))
                    .disabled(monitor.viewingMode == .recordings ? recordings.loading : monitor.paused)
                Button { playbackWindow.toggleFullScreen() } label: { Label(L10n.text("fullScreen"), systemImage: "arrow.up.left.and.arrow.down.right") }.help(L10n.text("fullScreenHelp"))
                AppearanceButton()
                Button { settingsVisible = true } label: { Label(L10n.text("settings"), systemImage: "gearshape") }.help(L10n.text("serverHelp"))
            }
        }
        .onChange(of: monitor.focusedID) { _, _ in choosingTVChannel = false }
        .onChange(of: language.language) { _, _ in monitor.updateProgramme() }
    }

    private var serverStatus: some View {
        HStack(spacing: 12) {
            Circle().fill(monitor.connected ? Color.green : Color.orange).frame(width: 7, height: 7)
                .accessibilityLabel(monitor.connected ? L10n.text("connected") : L10n.text("disconnected"))
            Text(monitor.connection.baseURL?.host ?? L10n.text("noServer")).font(.system(size: 13, weight: .medium))
            TunerStatusSummary(monitor: monitor)
        }
    }

    private var channelControls: some View {
        HStack(spacing: 8) {
            if let tuner = monitor.tuners.first(where: { $0.id == focusedID }) {
                Button { monitor.switchFocusedChannel(direction: -1) } label: { Image(systemName: "chevron.up") }
                    .help(L10n.text("previousChannelHelp")).accessibilityLabel(L10n.text("previousChannel"))
                    .disabled(!monitor.canSwitchFocusedChannel)
                Button { monitor.switchFocusedChannel(direction: 1) } label: { Image(systemName: "chevron.down") }
                    .help(L10n.text("nextChannelHelp")).accessibilityLabel(L10n.text("nextChannel"))
                    .disabled(!monitor.canSwitchFocusedChannel)
                Button { choosingTVChannel = true } label: { Label(L10n.text("chooseChannel"), systemImage: "list.bullet") }
                    .popover(isPresented: $choosingTVChannel, arrowEdge: .bottom) {
                        ChannelSelectionView(monitor: monitor, tuner: tuner) { choosingTVChannel = false }
                    }
            }
            if monitor.viewingMode == .mosaic {
                Button { monitor.occupyAllTuners() } label: {
                    Label(L10n.text("occupyAllTuners"), systemImage: "antenna.radiowaves.left.and.right")
                }.help(L10n.text("occupyAllTunersHelp")).disabled(!monitor.canOccupyAllTuners)
                Button { monitor.followAll() } label: { Label(L10n.text("followAll"), systemImage: "arrow.triangle.2.circlepath") }
                    .help(L10n.text("followAllHelp")).disabled(monitor.savedManual.isEmpty)
                if focusedID != nil {
                    Button { monitor.setViewingMode(.mosaic) } label: {
                        Label(L10n.text("allTuners"), systemImage: "square.grid.3x3")
                    }
                }
            }
            if monitor.paused { Label(L10n.text("paused"), systemImage: "pause.fill").font(.caption).foregroundStyle(ThemeColors.warning) }
        }
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer(minLength: 8)
            Button(L10n.text("settings")) { settingsVisible = true }
        }.padding(12).background(color.opacity(0.09)).padding(.horizontal, 14).padding(.bottom, 10)
    }

    private func placeholder(title: String, detail: String, symbol: String, loading: Bool) -> some View {
        VStack(spacing: 14) {
            if loading { ProgressView().controlSize(.large) }
            else { Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary) }
            Text(title).font(.title2.weight(.medium))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
            if monitor.tuners.isEmpty && !loading { Button(L10n.text("openSettings")) { settingsVisible = true } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TunerTile: View {
    @ObservedObject private var language = LanguageStore.shared
    let tuner: Tuner
    @ObservedObject var monitor: Monitor
    @ObservedObject var playback: Playback
    let focused: Bool
    let toggleFocus: () -> Void
    @State private var choosingChannel = false
    @State private var showingReception = false
    @State private var showingStatistics = false
    @AppStorage("lnbSwitchMHz") private var switchMHz = 11700.0

    private var preview: Preview? { monitor.preview(for: tuner) }
    private var headerTuner: Tuner { monitor.headerTuner(for: tuner) }
    private var active: Bool { preview != nil && monitor.connected && !monitor.paused }
    private var stateKey: String {
        if !monitor.connected { return "offline" }
        if monitor.paused { return "paused" }
        if monitor.manual[tuner.id] != nil { return "manualMode" }
        if monitor.savedManual[tuner.id] != nil { return "savedChannelMissing" }
        if preview != nil { return "followingMode" }
        if headerTuner.hasOwnPreview { return "ownPreview" }
        if headerTuner.unresolvedTV || !headerTuner.previews.isEmpty { return "unmappedTV" }
        return headerTuner.hasEPG ? "EPG" : "idle"
    }
    private var state: String { stateKey == "EPG" ? "EPG" : L10n.text(stateKey) }
    private var shortState: String {
        switch stateKey {
        case "manualMode": return "M"
        case "idle": return "F"
        default: return state
        }
    }
    private var stateColor: Color {
        if !monitor.connected || monitor.paused || headerTuner.unresolvedTV || monitor.savedManual[tuner.id] != nil && preview == nil { return ThemeColors.warning }
        return preview != nil || headerTuner.hasOwnPreview ? ThemeColors.active : .secondary
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(headerTuner.input.shortName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .help(headerTuner.input.input)
                Spacer(minLength: 0)
                Text(shortState).font(.system(size: 10, weight: .semibold)).foregroundStyle(stateColor).lineLimit(1)
                    .help(state).accessibilityLabel(state)
                Button { choosingChannel.toggle() } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.plain).help(L10n.text("chooseChannel"))
                    .accessibilityLabel(L10n.text("chooseChannelFor", headerTuner.input.shortName))
                    .popover(isPresented: $choosingChannel, arrowEdge: .bottom) {
                        ChannelSelectionView(monitor: monitor, tuner: tuner) { choosingChannel = false }
                    }
                Button { showingReception.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).help(L10n.text("receptionDetails"))
                    .accessibilityLabel(L10n.text("receptionFor", headerTuner.input.shortName))
                    .popover(isPresented: $showingReception, arrowEdge: .bottom) {
                        ReceptionDetailsView(monitor: monitor, tuner: tuner)
                    }
                if monitor.viewingMode != .tv { Button(action: toggleFocus) {
                    Image(systemName: focused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.plain).help(focused ? L10n.text("showAllTuners") : L10n.text("enlargeTuner"))
                    .accessibilityLabel(focused ? L10n.text("showAllTuners") : L10n.text("enlargeNamedTuner", headerTuner.input.shortName)) }
                if focused {
                    Button { showingStatistics.toggle() } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(showingStatistics ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain).disabled(!active)
                    .help(L10n.text(showingStatistics ? "hideStreamStatistics" : "showStreamStatistics"))
                    .accessibilityLabel(L10n.text(showingStatistics ? "hideStreamStatistics" : "showStreamStatistics"))
                    .accessibilityValue(L10n.text(showingStatistics ? "visible" : "hidden"))
                }
            }.padding(.horizontal, 10).frame(height: 28)

            ZStack {
                Color.black
                if active {
                    VideoSurface(playback: playback)
                    if !playback.isPlaying {
                        VStack(spacing: 7) {
                            if playback.status.contains("…") { ProgressView().controlSize(.small) }
                            Text(playback.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(12).allowsHitTesting(false)
                    }
                    VStack {
                        if !focused && monitor.showsRoutingNote(for: tuner) {
                            Text(L10n.text("previewVia", manualSources)).font(.system(size: 10))
                                .lineLimit(1).help(L10n.text("manualRoutingNote"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background { VideoControlsBackground(edge: .top) }
                        }
                        Spacer()
                        HStack {
                            if monitor.manual[tuner.id] == nil && tuner.previews.count > 1 {
                                Menu {
                                    ForEach(tuner.previews) { item in
                                        Button(item.title) { monitor.select(item, for: tuner) }
                                    }
                                } label: { Text(preview?.title ?? "TV").lineLimit(1) }
                                .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                                .help(L10n.text("selectPreviewHelp"))
                            } else {
                                Text(preview?.title ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button { monitor.toggleAudio(tuner.id) } label: {
                                Image(systemName: monitor.audioID == tuner.id ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            }.buttonStyle(.plain).help(monitor.audioID == tuner.id ? L10n.text("muteHelp") : L10n.text("unmuteHelp"))
                                .accessibilityValue(L10n.text(monitor.audioID == tuner.id ? "audioOn" : "audioMuted"))
                                .accessibilityLabel(L10n.text("audioForChannel", preview?.title ?? tuner.input.shortName))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background { VideoControlsBackground(edge: .bottom) }
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: !monitor.connected ? "wifi.slash" : headerTuner.hasOwnPreview ? "play.rectangle" : headerTuner.hasEPG ? "list.bullet.rectangle" : "tv")
                            .font(.system(size: 22, weight: .light)).foregroundStyle(Color(white: 0.48))
                        Text(idleTitle).font(.system(size: 12)).foregroundStyle(Color(white: 0.7))
                        if headerTuner.hasEPG && !headerTuner.hasOwnPreview && monitor.connected && !monitor.paused {
                            Text(L10n.text("epgNoVideo")).font(.system(size: 10)).foregroundStyle(Color(white: 0.58))
                        }
                    }.padding(8).multilineTextAlignment(.center)
                }
            }
            .overlay(alignment: .topLeading) {
                if focused && active && showingStatistics {
                    StreamStatisticsOverlay(playback: playback) { showingStatistics = false }
                        .padding(10).padding(.bottom, 36)
                }
            }
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .contentShape(Rectangle()).onTapGesture(count: 2, perform: toggleFocus)

            if !focused {
            Text(receptionSummary).font(.system(size: 10, weight: .medium)).monospacedDigit()
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 20)
                .help(receptionSummary)
            HStack(spacing: 8) {
                if let input = monitor.sources(for: tuner).only, input.stream != nil {
                    Text(input.signalLabel).lineLimit(1)
                    if focused, let snr = input.snrLabel { Text(snr) }
                    Spacer(minLength: 0)
                    Text(L10n.text("bitrate", L10n.decimal((input.bps ?? 0) / 1_000_000))).lineLimit(1)
                } else {
                    Text(L10n.text(monitor.manual[tuner.id] == nil ? "waitingChannel" : "tunerPending")).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                .padding(.horizontal, 10).frame(height: 28)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(!focused && monitor.audioID == tuner.id ? Color.accentColor : .primary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(headerTuner.input.shortName), \(state), \(preview?.title ?? "")")
    }

    private var manualSources: String {
        let sources = monitor.sources(for: tuner)
        return sources.isEmpty ? L10n.text("tunerPending") : sources.map(\.shortName).joined(separator: ", ")
    }

    private var receptionSummary: String {
        monitor.displayedMultiplex(for: tuner)?.summary(switchMHz: switchMHz) ??
            (monitor.manual[tuner.id] == nil ? headerTuner.input.stream : nil) ?? L10n.text("noActiveMultiplex")
    }

    private var idleTitle: String {
        if !monitor.connected { return L10n.text("connectionInterrupted") }
        if monitor.paused { return L10n.text("previewPaused") }
        if monitor.savedManual[tuner.id] != nil && preview == nil { return L10n.text("savedChannelMissingHelp") }
        if headerTuner.unresolvedTV || !headerTuner.previews.isEmpty { return L10n.text("channelUnmapped") }
        if headerTuner.hasOwnPreview { return L10n.text("ownPreviewActive") }
        return headerTuner.hasEPG ? (headerTuner.input.stream?.components(separatedBy: " in ").first ?? L10n.text("loadingEPG")) : L10n.text("tunerIdle")
    }
}

private struct ConnectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system
    @ObservedObject var monitor: Monitor
    @ObservedObject var updater: UpdateChecker
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Connection
    @State private var error: AppError?
    @AppStorage("lnbSwitchMHz") private var switchMHz = 11700.0

    init(monitor: Monitor, updater: UpdateChecker) {
        self.monitor = monitor
        self.updater = updater
        _draft = State(initialValue: monitor.connection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("settings")).font(.title2.weight(.semibold))
            Picker(L10n.text("language"), selection: $language.language) {
                ForEach(AppLanguage.allCases) { option in LanguageOption(language: option).tag(option) }
            }
            .help(L10n.text("languageNote"))
            Picker(L10n.text("appearance"), selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in Text(option.title).tag(option) }
            }
            .help(L10n.text("appearanceNote"))
            Form {
                TextField(L10n.text("serverAddress"), text: $draft.address, prompt: Text("http://tvheadend.local:9981"))
                TextField(L10n.text("username"), text: $draft.username)
                SecureField(L10n.text("password"), text: $draft.password)
                Picker(L10n.text("authentication"), selection: $draft.auth) {
                    Text("Digest").tag("digest")
                    Text("Basic").tag("basic")
                    Text(L10n.text("noAuthentication")).tag("none")
                }
            }.textFieldStyle(.roundedBorder)
            Text(L10n.text("credentialsNote"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L10n.text("bandSwitchMHz"))
                TextField("11700", value: $switchMHz, format: .number.grouping(.never).precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                    .onChange(of: switchMHz) { _, value in
                        if !value.isFinite || value < 1000 || value > 100000 { switchMHz = 11700 }
                    }
            }
            Text(L10n.text("bandSwitchNote")).font(.caption).foregroundStyle(.secondary)
            Divider()
            PollingSettingsView(monitor: monitor)
            Divider()
            UpdateSettingsView(updater: updater)
            if let error { Text(error.localizedDescription).font(.callout).foregroundStyle(ThemeColors.warning) }
            HStack {
                Spacer()
                Button(L10n.text("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("connect")) {
                    do { try monitor.apply(draft); dismiss() }
                    catch { self.error = .wrapping(error) }
                }.keyboardShortcut(.defaultAction).disabled(draft.baseURL == nil)
            }
        }.padding(26).frame(width: 470)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
