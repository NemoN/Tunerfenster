import SwiftUI

@MainActor
final class Monitor: ObservableObject {
    @Published var connection = Connection(address: "http://tvheadend.local:9981", username: "", password: "")
    @Published var tuners = [Tuner]()
    @Published var error: AppError?
    @Published var catalogWarning: AppError?
    @Published var connected = false
    @Published var paused = false
    @Published var loading = true
    @Published var lastUpdate: Date?
    @Published private(set) var pollingSeconds: Int
    @Published var audioID: String?
    @Published private(set) var viewingMode: ViewingMode = .mosaic
    @Published private(set) var focusedID: String?
    @Published private(set) var programme: ProgrammeSchedule?
    @Published private(set) var programmeError: AppError?
    @Published private(set) var programmeLoading = false
    @Published private(set) var channelIconRevision = 0
    @Published var selected = [String: Int]()
    @Published private(set) var manual = [String: StreamChoice]()
    @Published private(set) var savedManual = [String: String]()
    @Published private(set) var choices = [StreamChoice]()
    @Published private(set) var receptionWarning: AppError?
    @Published private(set) var tunerAllocation: TunerAllocation?
    let recorder = Recorder()
    let recordings = RecordingLibrary()
    private var multiplexes = [Multiplex]()
    private var subscriptions = [Subscription]()
    private var players = [String: Playback]()
    private var api: API?
    private var polling: Task<Void, Never>?
    private var pollingSleep: Task<Void, Never>?
    private let preferences: UserDefaults
    private var refreshing = false
    private var generation = UUID()
    private var playbackRevision = UUID()
    private var lastTVTunerID: String?
    private var pendingViewingInteraction = false
    private var suppressAutomaticAudio = false
    private var services = [Service]()
    private var channels = [Channel]()
    private var catalogDate = Date.distantPast
    private var tickets = [String: (url: URL, date: Date)]()
    private let selectionStore: SelectionStore
    private var selectionScope: String?
    private var focusedAudioPath: String?
    private var programmeTask: Task<Void, Never>?
    private var programmeRequest: String?
    private let channelIcons = NSCache<NSURL, NSImage>()

    init(selectionStore: SelectionStore = SelectionStore(), preferences: UserDefaults = .standard) {
        self.selectionStore = selectionStore
        self.preferences = preferences
        pollingSeconds = PollingInterval.load(from: preferences)
        channelIcons.countLimit = 32
        channelIcons.totalCostLimit = 8_000_000
    }

    var liveCount: Int { playbackTuners.filter { preview(for: $0) != nil }.count }
    var busyTunerCount: Int { tuners.filter { ($0.input.subs ?? 0) > 0 }.count }
    var tunerUsage: [TunerUsage] { TunerUsage.overview(tuners: tuners, subscriptions: subscriptions) }
    var epgCount: Int { tuners.filter { $0.hasEPG && preview(for: $0) == nil }.count }

    var playbackTuners: [Tuner] {
        switch viewingMode {
        case .mosaic: return tuners
        case .tv: return tuners.filter { $0.id == focusedID }
        case .recordings: return []
        }
    }

    func setViewingMode(_ mode: ViewingMode) {
        if mode != .mosaic { tunerAllocation = nil }
        recordings.setActive(mode == .recordings)
        enableFocusedAudio()
        viewingMode = mode
        if mode == .tv {
            ensureTVSelection()
        } else {
            focus(nil)
        }
        updateFocusedAudio()
        saveViewingState()
        requestReconciliation()
    }

    var canSelectFocusedTuner: Bool {
        guard viewingMode != .recordings, let id = focusedID, tuners.contains(where: { $0.id == id }) else { return false }
        // A saved channel remains manual while the channel catalogue is unavailable.
        return savedManual[id] == nil && manual[id] == nil
    }

    func selectFocusedTuner(_ id: String) {
        guard canSelectFocusedTuner, tuners.contains(where: { $0.id == id }) else { return }
        lastTVTunerID = id
        focus(id)
        requestReconciliation()
    }

    func ensureTVSelection() {
        guard viewingMode == .tv else { return }
        let target = tuners.first { $0.id == lastTVTunerID } ?? tuners.first { $0.id == focusedID } ??
            tuners.first { preview(for: $0) != nil } ?? tuners.first
        // Keep the preferred tuner through an empty status response or a temporary
        // outage. A fallback must not replace the user's saved choice.
        if lastTVTunerID == nil, let target {
            lastTVTunerID = target.id
            saveViewingState()
        }
        guard focusedID != target?.id else { return }
        setFocusedID(target?.id)
        playbackRevision = UUID()
    }

    func followAll() {
        tunerAllocation = nil
        let changed = Set(savedManual.keys).union(manual.keys)
        manual.removeAll()
        savedManual.removeAll()
        saveSelections()
        for id in changed { players[id]?.stop() }
        updateFocusedAudio()
        updateProgramme()
        requestReconciliation()
    }

    var canOccupyAllTuners: Bool {
        connected && !paused && !tuners.isEmpty && choices.contains { $0.mapped && TunerAllocation.carrierKey(for: $0) != nil }
    }

    func occupyAllTuners() {
        guard canOccupyAllTuners else { return }
        let current = Dictionary(tuners.compactMap { tuner in currentChoice(for: tuner).map { (tuner.id, $0) } },
                                 uniquingKeysWith: { first, _ in first })
        let plan = TunerAllocation.plan(tuners: tuners, choices: choices, current: current)
        guard !plan.assignments.isEmpty else { return }
        var selections = manual, saved = savedManual
        for (id, choice) in plan.assignments {
            if let tuner = tuners.first(where: { $0.id == id }), preview(for: tuner)?.path != choice.preview.path {
                players[id]?.stop()
            }
            selections[id] = choice
            saved[id] = choice.id
        }
        manual = selections; savedManual = saved
        saveSelections()
        tunerAllocation = plan
        setViewingMode(.mosaic)
        updateProgramme()
    }

    func dismissTunerAllocation() { tunerAllocation = nil }

    private func requestReconciliation() {
        playbackRevision = UUID()
        let allowed = Set(playbackTuners.map(\.id))
        for (id, player) in players where !allowed.contains(id) { player.setMuted(true); player.stop() }
        Task { await reconcile() }
    }

    func preview(for tuner: Tuner) -> Preview? {
        if let choice = manual[tuner.id] { return choice.preview }
        if savedManual[tuner.id] != nil { return nil }
        return tuner.previews.first { $0.id == selected[tuner.id] } ?? tuner.previews.first
    }

    func currentChoice(for tuner: Tuner) -> StreamChoice? {
        StreamChoice.current(for: preview(for: tuner), input: tuner.input, choices: choices, channels: channels)
    }

    var canSwitchFocusedChannel: Bool {
        guard viewingMode != .recordings, let tuner = tuners.first(where: { $0.id == focusedID }) else { return false }
        return connected && !paused && choices.filter { $0.mapped && $0.matches(input: tuner.input) }.count > 1
    }

    func switchFocusedChannel(direction: Int) {
        guard canSwitchFocusedChannel, let tuner = tuners.first(where: { $0.id == focusedID }),
              let choice = StreamChoice.adjacent(to: currentChoice(for: tuner)?.id, direction: direction,
                                                input: tuner.input, choices: choices) else { return }
        choose(choice, for: tuner)
    }

    func setPollingSeconds(_ seconds: Int) {
        let value = PollingInterval.validated(seconds)
        guard value != pollingSeconds else { return }
        pollingSeconds = value
        preferences.set(value, forKey: PollingInterval.key)
        // Wake the interval wait so the new duration takes effect. Current
        // requests and VLC streams keep running.
        pollingSleep?.cancel()
    }

    func choose(_ choice: StreamChoice?, for tuner: Tuner) {
        tunerAllocation = nil
        manual[tuner.id] = choice
        savedManual[tuner.id] = choice?.id
        saveSelections()
        if focusedID == tuner.id { enableFocusedAudio() }
        updateFocusedAudio()
        updateProgramme()
        // Stop the previous channel immediately, even while its ticket request is pending.
        players[tuner.id]?.stop()
        requestReconciliation()
    }

    func loadSelections(for connection: Connection) {
        selectionScope = SelectionStore.scope(for: connection)
        savedManual = selectionScope.map { selectionStore.load(scope: $0) } ?? [:]
        manual = [:]
        let state = selectionScope.map { selectionStore.loadViewingState(scope: $0) } ?? ViewingState()
        if !pendingViewingInteraction {
            viewingMode = state.mode
            lastTVTunerID = state.tunerID
            suppressAutomaticAudio = true
            focusedAudioPath = nil
            setAudio(nil)
            focusedID = nil
        } else if lastTVTunerID == nil {
            lastTVTunerID = state.tunerID
        }
        pendingViewingInteraction = false
        saveViewingState()
    }

    private func saveSelections() {
        if let selectionScope { selectionStore.save(savedManual, scope: selectionScope) }
    }

    private func saveViewingState() {
        guard let selectionScope else { pendingViewingInteraction = true; return }
        selectionStore.saveViewingState(ViewingState(mode: viewingMode, tunerID: lastTVTunerID), scope: selectionScope)
    }

    private func enableFocusedAudio() {
        if suppressAutomaticAudio { suppressAutomaticAudio = false; focusedAudioPath = nil }
    }

    func resolveSelections() {
        let ids = Set(tuners.map(\.id))
        let catalog = Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        manual = savedManual.reduce(into: [:]) { result, item in
            if ids.contains(item.key), let choice = catalog[item.value] { result[item.key] = choice }
        }
    }

    func focus(_ id: String?) {
        guard viewingMode != .recordings || id == nil else { return }
        enableFocusedAudio()
        if let id { lastTVTunerID = id }
        setFocusedID(id)
        updateFocusedAudio()
        saveViewingState()
    }

    private func setFocusedID(_ id: String?) {
        guard focusedID != id else { return }
        focusedID = id
        focusedAudioPath = nil
        setAudio(nil)
        updateFocusedAudio()
        updateProgramme()
    }

    func updateFocusedAudio() {
        let preview = focusedID.flatMap { id in tuners.first { $0.id == id } }.flatMap { preview(for: $0) }
        let path = connected && !paused ? preview?.path : nil
        guard path != focusedAudioPath else { return }
        focusedAudioPath = path
        setAudio(path == nil || suppressAutomaticAudio ? nil : focusedID)
    }

    var programmeChannel: Channel? {
        guard let id = focusedID, let tuner = tuners.first(where: { $0.id == id }), let preview = preview(for: tuner) else { return nil }
        return ProgrammeSchedule.channel(for: preview, channels: channels)
    }

    func channelIcon(for channel: Channel) async -> NSImage? {
        guard connected, let api, let url = api.channelIconURL(for: channel) else { return nil }
        if let cached = channelIcons.object(forKey: url as NSURL) { return cached }
        let token = generation
        do {
            guard let data = try await api.channelIconData(from: url), !Task.isCancelled,
                  token == generation, let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0 else { return nil }
            channelIcons.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        } catch { return nil }
    }

    func updateProgramme(force: Bool = false) {
        guard connected, !paused, let api, let id = focusedID,
              let tuner = tuners.first(where: { $0.id == id }), let preview = preview(for: tuner),
              let channel = programmeChannel else { clearProgramme(); return }
        let language = L10n.language
        let request = [id, preview.path, channel.uuid, language.rawValue].joined(separator: "\n")
        guard force || request != programmeRequest else { return }
        clearProgramme()
        programmeRequest = request
        programmeLoading = true
        let token = generation
        programmeTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let schedule = try await api.programmeSchedule(channelID: channel.uuid, language: language)
                    guard let self, !Task.isCancelled, self.generation == token, self.programmeRequest == request else { return }
                    self.programme = schedule
                    self.programmeError = nil
                    self.programmeLoading = false
                } catch {
                    guard let self, !Task.isCancelled, self.generation == token, self.programmeRequest == request else { return }
                    self.programmeError = .context("programmeUnavailable", .wrapping(error))
                    self.programmeLoading = false
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func clearProgramme() {
        programmeTask?.cancel(); programmeTask = nil; programmeRequest = nil
        programme = nil; programmeError = nil; programmeLoading = false
    }

    func physicalMultiplex(for tuner: Tuner) -> Multiplex? {
        Snapshot.multiplex(for: tuner.input, multiplexes: multiplexes)
    }

    func displayedMultiplex(for tuner: Tuner) -> Multiplex? {
        if let choice = manual[tuner.id] { return choice.multiplex }
        return physicalMultiplex(for: tuner)
    }

    func sources(for tuner: Tuner) -> [Input] {
        guard let choice = manual[tuner.id] else { return [tuner.input] }
        return Snapshot.sources(for: choice.service, inputs: tuners.map(\.input), subscriptions: subscriptions)
    }

    func player(for id: String) -> Playback {
        if let player = players[id] { return player }
        let player = Playback()
        players[id] = player
        return player
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            // Reading a file in Documents can wait for macOS file-access consent.
            // Let the window appear first and keep that wait off AppKit's thread.
            let initial = await Task.detached(priority: .userInitiated) { Connection.initial() }.value
            guard !Task.isCancelled, let self else { return }
            self.connection = initial
            if ProcessInfo.processInfo.arguments.contains("--import-connection-stdin") {
                do { try initial.save() }
                catch {
                    self.error = .wrapping(error); self.loading = false; self.polling = nil
                    return
                }
            }
            self.loadSelections(for: initial)
            self.api = API(connection: initial)
            self.recorder.configure(self.api)
            self.recordings.configure(self.api)
            self.recordings.setActive(self.viewingMode == .recordings)
            while !Task.isCancelled {
                if !self.paused { await self.refresh() }
                guard !Task.isCancelled else { return }
                let seconds = self.pollingSeconds
                let wait = Task<Void, Never> { try? await Task.sleep(for: .seconds(seconds)) }
                self.pollingSleep = wait
                await withTaskCancellationHandler(operation: { await wait.value }, onCancel: { wait.cancel() })
            }
        }
    }

    func shutdown() {
        tunerAllocation = nil
        saveSelections()
        saveViewingState()
        clearProgramme()
        generation = UUID()
        recorder.configure(nil)
        recordings.configure(nil)
        polling?.cancel()
        pollingSleep?.cancel()
        pollingSleep = nil
        polling = nil
        api?.close()
        api = nil
        stopPlayers()
        focusedID = nil
    }

    func apply(_ connection: Connection) throws {
        try connection.save()
        shutdown()
        self.connection = connection
        services = []; channels = []; tuners = []; players = [:]; tickets = [:]
        multiplexes = []; choices = []; manual = [:]; savedManual = [:]; subscriptions = []; receptionWarning = nil
        channelIcons.removeAllObjects()
        catalogDate = .distantPast
        selectionScope = nil; pendingViewingInteraction = false
        error = nil; connected = false; loading = true; refreshing = false; paused = false
        start()
    }

    func togglePause() {
        tunerAllocation = nil
        paused.toggle()
        if paused { stopPlayers() }
        else { Task { await refresh() } }
        updateProgramme()
    }

    func toggleAudio(_ id: String) {
        suppressAutomaticAudio = false
        setAudio(audioID == id ? nil : id)
    }

    func toggleMute() {
        if viewingMode == .recordings { recordings.toggleMute(); return }
        guard connected, !paused else { return }
        if let audioID { toggleAudio(audioID); return }
        let target = focusedID.flatMap { id in playbackTuners.first { $0.id == id } } ??
            (focusedID == nil ? playbackTuners.first { preview(for: $0) != nil } : nil)
        if let target, preview(for: target) != nil { toggleAudio(target.id) }
    }

    private func setAudio(_ id: String?) {
        audioID = id
        for (key, player) in players { player.setMuted(key != audioID) }
    }

    func select(_ preview: Preview, for tuner: Tuner) {
        selected[tuner.id] = preview.id
        if focusedID == tuner.id { enableFocusedAudio() }
        updateFocusedAudio()
        updateProgramme()
        requestReconciliation()
    }

    private func stopPlayers() {
        setAudio(nil)
        for player in players.values { player.stop() }
        focusedAudioPath = nil
    }

    func refresh(reloadCatalog: Bool = false) async {
        guard !refreshing, !paused, let api else { return }
        refreshing = true
        let token = generation
        defer { if token == generation { refreshing = false; loading = false } }
        do {
            // Establish status connectivity before loading the larger catalog. A
            // temporary first-connection failure must not delay mapping for 30 s.
            async let inputData: GridResponse<Input> = api.read("status/inputs")
            async let subData: GridResponse<Subscription> = api.read("status/subscriptions")
            let (inputs, subscriptions) = try await (inputData, subData)
            guard token == generation, !Task.isCancelled else { return }
            if reloadCatalog || Date().timeIntervalSince(catalogDate) > 600 {
                do {
                    async let serviceItems: [Service] = api.all("mpegts/service/grid")
                    async let channelItems: [Channel] = api.all("channel/grid")
                    let (s, c) = try await (serviceItems, channelItems)
                    guard token == generation, !Task.isCancelled else { return }
                    services = s; channels = c; catalogWarning = nil
                    channelIcons.removeAllObjects()
                    channelIconRevision += 1
                    do {
                        multiplexes = try await api.all("mpegts/mux/grid")
                        receptionWarning = nil
                    } catch {
                        receptionWarning = .context("receptionUnavailable", .wrapping(error))
                    }
                    guard token == generation, !Task.isCancelled else { return }
                    choices = StreamChoice.catalog(services: services, channels: channels, multiplexes: multiplexes)
                    catalogDate = Date()
                } catch {
                    guard token == generation, !Task.isCancelled else { return }
                    catalogWarning = .context("catalogUnavailable", .wrapping(error))
                    // A status-only account can still inspect tuner state. Retry the catalog later.
                    catalogDate = Date().addingTimeInterval(-597)
                }
            }
            tuners = Snapshot.tuners(inputs: inputs.entries, subscriptions: subscriptions.entries, services: services, channels: channels)
            self.subscriptions = subscriptions.entries
            resolveSelections()
            if viewingMode == .tv { ensureTVSelection() }
            else if let focusedID, !tuners.contains(where: { $0.id == focusedID }) { focus(nil) }
            connected = true; error = nil; lastUpdate = Date()
            updateProgramme()
            await reconcile()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            self.error = .wrapping(error)
            connected = false
            stopPlayers()
            clearProgramme()
        }
    }

    private func reconcile() async {
        guard connected, !paused, let api else { stopPlayers(); return }
        let token = generation
        let revision = playbackRevision
        updateFocusedAudio()
        let targets = playbackTuners
        let wanted = Set(targets.filter { preview(for: $0) != nil }.map(\.id))
        for (id, player) in players where !wanted.contains(id) { player.setMuted(true); player.stop() }
        for tuner in targets {
            guard token == generation, revision == playbackRevision, !paused, connected, !Task.isCancelled else { return }
            guard let preview = preview(for: tuner) else { continue }
            let player = player(for: tuner.id)
            do {
                let streamURL: URL
                if let ticket = tickets[preview.path], Date().timeIntervalSince(ticket.date) < 90 {
                    streamURL = ticket.url
                } else {
                    streamURL = try await api.ticketURL(for: preview)
                    guard token == generation, revision == playbackRevision, !paused, connected, !Task.isCancelled else { return }
                    tickets[preview.path] = (streamURL, Date())
                }
                guard let currentTuner = tuners.first(where: { $0.id == tuner.id }), self.preview(for: currentTuner)?.path == preview.path else { continue }
                player.start(url: streamURL, key: preview.path)
                player.setMuted(audioID != tuner.id)
                player.updateStatus()
            } catch {
                guard token == generation, revision == playbackRevision, !Task.isCancelled else { return }
                player.stop()
                self.error = .wrapping(error)
            }
        }
        for (id, player) in players where !wanted.contains(id) { player.stop() }
        if let audioID, !wanted.contains(audioID) { self.audioID = nil }
        let existing = Set(tuners.map(\.id))
        for id in Array(players.keys) where !existing.contains(id) { players.removeValue(forKey: id) }
    }
}
