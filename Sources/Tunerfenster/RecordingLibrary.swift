import Foundation
import Combine

struct RecordingText: Decodable, Equatable, Sendable {
    private let values: [String: String]
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { values = ["": text] }
        else { values = try value.decode([String: String].self) }
    }
    var localized: String? {
        [values[L10n.language == .german ? "ger" : "eng"], values[L10n.language.rawValue], values[""],
         values["eng"], values.keys.sorted().compactMap { values[$0] }.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

struct SavedRecording: Decodable, Equatable, Identifiable, Sendable {
    let uuid: String
    var disp_title: String? = nil
    var title: RecordingText? = nil
    var disp_subtitle: String? = nil
    var subtitle: RecordingText? = nil
    var disp_description: String? = nil
    var description: RecordingText? = nil
    var disp_summary: String? = nil
    var summary: RecordingText? = nil
    var channelname: String? = nil
    var channel: String? = nil
    var start: Double? = nil
    var stop: Double? = nil
    var duration: Double? = nil
    var fileDuration: Double? = nil
    var filesize: Int64? = nil
    var sched_status: String? = nil
    var status: String? = nil
    var url: String? = nil
    var filename: String? = nil
    var directory: String? = nil
    var config_name: String? = nil
    var files: [RecordingFile]? = nil
    var playposition: Double? = nil
    var playcount: Int? = nil
    var watched: Double? = nil
    var progress: RecordingProgress { .init(playposition: playposition, playcount: playcount, watched: watched) }
    var id: String { uuid }
    var name: String {
        guard let base = text(disp_title) ?? title?.localized else { return L10n.text("untitledRecording") }
        return RecordingTitle.display(base, subtitle: subtitleText, detail: detail)
    }
    var detail: String? { text(disp_description) ?? description?.localized ?? text(disp_summary) ?? summary?.localized }
    var subtitleText: String? { text(disp_subtitle) ?? subtitle?.localized }
    var isRunning: Bool { ["recording", "recordingError"].contains(sched_status ?? "") }
    var canDelete: Bool {
        uuid.count == 32 && uuid.allSatisfy(\.isHexDigit) && (sched_status ?? "").hasPrefix("completed")
    }
    var isExisting: Bool { !uuid.isEmpty && (isRunning || (sched_status ?? "").hasPrefix("completed") || (filesize ?? 0) > 0) }
    var canPlay: Bool { isExisting && filesize != 0 && (text(url) != nil || (filesize ?? 0) > 0) }
    var hasError: Bool { ["recordingError", "completedError", "completedWarning"].contains(sched_status ?? "") }
    var statusLabel: String {
        L10n.text(!canPlay ? "recordingFileUnavailable" : isRunning ? "recordingInProgress" : hasError ? "recordingWithErrors" : "recordingCompleted")
    }
    var dateLabel: String? {
        recordingDate.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.language.locale)) }
    }
    var compactDateLabel: String? {
        listDateLabel(locale: L10n.language.locale)
    }
    func listDateLabel(locale: Locale, timeZone: TimeZone = .current) -> String? {
        recordingDate.map {
            $0.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: locale, timeZone: timeZone)
                .day(.twoDigits).month(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
    }
    private var recordingDate: Date? {
        guard let start, start.isFinite else { return nil }
        return Date(timeIntervalSince1970: start)
    }
    var recordedDuration: Double {
        let value: Double
        if let fileDuration, fileDuration.isFinite, fileDuration > 0 { value = fileDuration }
        else if let duration { value = duration }
        else if let start, let stop { value = stop - start }
        else { return 0 }
        return value.isFinite ? max(0, value) : 0
    }
    var compactDurationLabel: String? {
        let value = recordedDuration
        guard value >= 1, value < Double(Int.max) else { return nil }
        let seconds = Int(value)
        return String(seconds / 3600) + String(format: ":%02d:%02d", seconds / 60 % 60, seconds % 60)
    }
    func matches(_ search: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || [name, channelname, subtitleText, detail].compactMap { $0 }.contains { $0.localizedStandardContains(term) }
    }
    private func text(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }
}

enum RecordingChannel {
    static func resolve(_ recording: SavedRecording, channels: [Channel]) -> Channel? {
        if let id = recording.channel?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return channels.first { $0.uuid == id }
        }
        guard let name = recording.channelname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let matches = channels.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }
}

protocol RecordingLibraryAPI: Sendable {
    func savedRecordings() async throws -> [SavedRecording]
    func recordingStorageRoots() async throws -> [RecordingStorage]
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL
    func deleteRecording(uuid: String) async throws
    func recordingProgress(uuid: String) async throws -> RecordingProgress
    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress
    func commercialData(for recording: SavedRecording, endpoint: CommercialEndpoint) async throws -> RecordingCommercialData
    func recordingFileDurations(for recordings: [SavedRecording], endpoint: CommercialEndpoint) async throws -> [String: Double]
}

extension RecordingLibraryAPI {
    func commercialData(for recording: SavedRecording, endpoint: CommercialEndpoint) async throws -> RecordingCommercialData { .init() }
    func recordingFileDurations(for recordings: [SavedRecording], endpoint: CommercialEndpoint) async throws -> [String: Double] { [:] }
}

private struct RecordingDeletionResponse: Decodable {}

extension API: RecordingLibraryAPI {
    func recordingFileDurations(for recordings: [SavedRecording], endpoint: CommercialEndpoint) async throws -> [String: Double] {
        try await HTSPCommercials.loadFileDurations(recordings: recordings, connection: connection, endpoint: endpoint)
    }

    func commercialData(for recording: SavedRecording, endpoint: CommercialEndpoint) async throws -> RecordingCommercialData {
        guard RecordingProgressOutbox.validUUID(recording.id) else { throw AppError.message("commercialRecordingMissing") }
        return try await HTSPCommercials.load(recording: recording, connection: connection, endpoint: endpoint)
    }

    func savedRecordings() async throws -> [SavedRecording] { try await all("dvr/entry/grid") }
    func recordingStorageRoots() async throws -> [RecordingStorage] { try await all("dvr/config/grid") }

    func recordingProgress(uuid: String) async throws -> RecordingProgress {
        guard RecordingProgressOutbox.validUUID(uuid) else { throw AppError.message("recordingFileUnavailable") }
        let result: GridResponse<SavedRecording> = try await read("idnode/load", query: [
            .init(name: "uuid", value: uuid), .init(name: "grid", value: "1"),
            .init(name: "list", value: "playposition,playcount,watched,sched_status,filesize,url")
        ])
        guard let entry = result.entries.first(where: { $0.id == uuid }), entry.isExisting,
              entry.playposition != nil, entry.playcount != nil else { throw AppError.message("recordingProgressUnavailable") }
        return entry.progress
    }

    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress {
        guard RecordingProgressOutbox.validUUID(uuid), (0...Int(UInt32.max)).contains(checkpoint.position) else {
            throw AppError.message("recordingProgressUnavailable")
        }
        let current = try await recordingProgress(uuid: uuid)
        struct Update: Encodable { let uuid: String; let playposition: Int; let playcount: Int? }
        // Position updates preserve watched marks. Only an explicit Unwatched
        // action resets the counter. Retries never increment it again.
        let desiredSeen = checkpoint.seenOverride ?? (checkpoint.seen ? true : nil)
        let count = desiredSeen.map { $0 ? max(1, current.playcount ?? 0) : 0 }
        guard count.map({ (0...Int(UInt32.max)).contains($0) }) ?? true else { throw AppError.message("recordingProgressUnavailable") }
        let data = try JSONEncoder().encode(Update(uuid: uuid, playposition: checkpoint.position, playcount: count))
        let _: RecordingDeletionResponse = try await post("idnode/save", form: [
            .init(name: "node", value: String(decoding: data, as: UTF8.self))
        ])
        let saved = try await recordingProgress(uuid: uuid)
        guard saved.position == checkpoint.position, desiredSeen.map({ saved.seen == $0 }) ?? true else {
            throw AppError.message("recordingProgressUnconfirmed")
        }
        return saved
    }

    func deleteRecording(uuid: String) async throws {
        guard uuid.count == 32, uuid.allSatisfy(\.isHexDigit) else { throw AppError.message("recordingDeleteChanged") }
        // The DVR class's delete action removes both its files and its entry.
        // The library revalidates this single UUID against the DVR grid first.
        let _: RecordingDeletionResponse = try await post("idnode/delete", form: [URLQueryItem(name: "uuid", value: uuid)])
    }

    func recordingTicketURL(for recording: SavedRecording) async throws -> URL {
        // Construct the DVR endpoint ourselves; never follow an arbitrary file
        // URL from the catalogue or send credentials to another origin.
        guard recording.uuid.count == 32, recording.uuid.allSatisfy({ $0.isHexDigit }), recording.canPlay else {
            throw AppError.message("recordingFileUnavailable")
        }
        let preview = Preview(id: -1, title: recording.name, path: "dvrfile/\(recording.uuid)", sourceState: "")
        let result = try await ticketURL(for: preview)
        guard result.path == (try streamURL(for: preview)).path, result.fragment == nil else { throw AppError.message("invalidTicket") }
        return result
    }
}

@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var items = [SavedRecording]()
    @Published private(set) var storageRoots = [RecordingStorage]()
    @Published private(set) var selected: SavedRecording?
    @Published private(set) var loading = false
    @Published private(set) var configured = false
    @Published private(set) var opening = false
    @Published private(set) var playbackRequested = false
    @Published private(set) var error: AppError?
    @Published private(set) var playbackError: AppError?
    @Published private(set) var muted = true
    @Published private(set) var deletionCandidate: SavedRecording?
    @Published private(set) var deletingID: String?
    @Published private(set) var deletionError: AppError?
    @Published private(set) var commercialBreaks = [CommercialBreak]()
    @Published private(set) var commercialFileDuration: Double?
    private(set) var commercialsLoading = false
    private(set) var commercialsError: AppError?
    var didDelete: ((String) -> Void)?
    let playback = Playback()
    private var api: (any RecordingLibraryAPI)?
    private var active = false
    private var refreshing = false
    private var generation = UUID()
    private var playRequest = UUID()
    private let listCache = RecordingListCache()
    private let progressSync = RecordingProgressSync()
    private var progressSession: RecordingProgressSession?
    let commercialPreferences: CommercialPreferences
    private var commercialsTask: Task<Void, Never>?
    private var commercialsRequest = UUID()
    private var commercialsChecked = Date.distantPast
    private var commercialSkip = CommercialSkipState()
    private var timelineEditing = false
    private var fileDurations = [String: Double]()
    private var fileDurationsTask: Task<Void, Never>?
    private var fileDurationsRequest = UUID()
    private var fileDurationsChecked = Date.distantPast
    private var fileDurationsEndpoint: CommercialEndpoint?

    init(commercialPreferences: CommercialPreferences? = nil) {
        self.commercialPreferences = commercialPreferences ?? .shared
        progressSync.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    var progressError: AppError? { progressSync.error }
    func progress(for recording: SavedRecording) -> RecordingProgress { progressSync.state(for: recording) }

    func canMarkSeen(_ recording: SavedRecording) -> Bool {
        active && api != nil && !loading && deletingID != recording.id && RecordingProgressOutbox.validUUID(recording.id) &&
            items.contains { $0.id == recording.id }
    }

    func markSeen(_ seen: Bool, for recording: SavedRecording) {
        guard canMarkSeen(recording) else { return }
        if selected?.id == recording.id {
            progressSession?.markManually(seen: seen, at: playback.positionSeconds)
        }
        progressSync.enqueue(.init(position: 0, seen: seen, seenOverride: seen), for: recording, force: true)
    }

    func configure(_ api: (any RecordingLibraryAPI)?) {
        setActive(false)
        progressSync.configure(api, scope: (api as? API).flatMap { SelectionStore.scope(for: $0.connection) })
        self.api = api
        configured = api != nil
        fileDurations = [:]; fileDurationsChecked = .distantPast; fileDurationsEndpoint = nil
        listCache.invalidate()
        items = []; storageRoots = []; error = nil
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        if !value { checkpointProgress(force: true); progressSession = nil }
        active = value
        generation = UUID(); playRequest = UUID()
        fileDurationsTask?.cancel(); fileDurationsTask = nil; fileDurationsRequest = UUID()
        refreshing = false; loading = false; opening = false
        deletionCandidate = nil; deletingID = nil; deletionError = nil
        if value { Task { await refresh() } }
        else {
            clearCommercials()
            selected = nil; playbackError = nil
            playbackRequested = false
            playback.setMuted(true); playback.stop(); muted = true
        }
    }

    func refresh(background: Bool = false) async {
        guard active, let api, !refreshing, deletingID == nil else { return }
        refreshing = true
        if !background || items.isEmpty { loading = true }
        let token = generation
        let progressRevision = progressSync.revision
        defer { if token == generation { refreshing = false; if loading { loading = false } } }
        do {
            async let roots = try? api.recordingStorageRoots()
            let result = try await api.savedRecordings()
            let storage = await roots
            guard token == generation, deletingID == nil, !Task.isCancelled else { return }
            if let storage, storage != storageRoots {
                storageRoots = storage
                listCache.invalidate()
            }
            updateItems(result, progressRevision: progressRevision)
            loadFileDurations()
            loadCommercials()
            if error != nil { error = nil }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            if !background || items.isEmpty { self.error = .context("recordingsUnavailable", .wrapping(error)) }
        }
    }

    var folderTree: RecordingFolderTree { RecordingFolderTree(items: items, storageRoots: storageRoots) }

    func listSnapshot(sort: RecordingSort, search: String) -> RecordingListSnapshot {
        listCache.snapshot(items: items, storageRoots: storageRoots, sort: sort, search: search)
    }

    private func updateItems(_ result: [SavedRecording], progressRevision: Int? = nil) {
        // The grid also contains future timers. Keep recorded files and
        // recordings in progress, including partial files with errors.
        let existing = result.filter(\.isExisting)
        let ids = Set(existing.map(\.id))
        fileDurations = fileDurations.filter { ids.contains($0.key) }
        var unique = [String: SavedRecording]()
        for recording in existing where unique[recording.id] == nil {
            var item = recording
            item.fileDuration = fileDurations[item.id] ?? item.fileDuration
            unique[item.id] = item
        }
        let updated = unique.values.sorted {
            ($0.start ?? 0) == ($1.start ?? 0) ? $0.id < $1.id : ($0.start ?? 0) > ($1.start ?? 0)
        }
        if updated != items {
            listCache.invalidate()
            items = updated
        }
        progressSync.merge(items, since: progressRevision ?? progressSync.revision)
        if let selected {
            if let fresh = items.first(where: { $0.id == selected.id }) {
                if playbackRequested && !fresh.canPlay {
                    stopPlayback()
                    playbackError = .message("recordingFileUnavailable")
                }
                if fresh != selected { self.selected = fresh }
            } else {
                stopPlayback()
                playbackError = .message("recordingFileUnavailable")
            }
        }
    }

    func canDelete(_ recording: SavedRecording) -> Bool {
        active && api != nil && !loading && deletingID == nil && recording.canDelete &&
            items.first(where: { $0.id == recording.id })?.canDelete == true
    }

    func requestDeletion(_ recording: SavedRecording) {
        guard canDelete(recording) else { return }
        deletionError = nil
        deletionCandidate = recording
    }

    func cancelDeletion() { deletionCandidate = nil }
    func dismissDeletionError() { deletionError = nil }

    @discardableResult func confirmDeletion() -> Task<Void, Never>? {
        guard let recording = deletionCandidate, canDelete(recording), let api else {
            deletionCandidate = nil
            return nil
        }
        deletionCandidate = nil
        deletingID = recording.id
        deletionError = nil
        let token = generation
        return Task {
            defer { if token == generation { deletingID = nil } }
            do {
                let catalogue = try await api.savedRecordings()
                guard token == generation, active, !Task.isCancelled else { return }
                if let fresh = catalogue.first(where: { $0.id == recording.id }) {
                    guard fresh.canDelete else { throw AppError.message("recordingDeleteChanged") }
                    try await api.deleteRecording(uuid: recording.id)
                    guard token == generation, active else { return }
                    let remaining = try await api.savedRecordings()
                    guard token == generation, active else { return }
                    guard !remaining.contains(where: { $0.id == recording.id }) else {
                        throw AppError.message("recordingDeleteUnconfirmed")
                    }
                    finishDeletion(recording, catalogue: remaining)
                } else {
                    // Another client has already removed this entry.
                    finishDeletion(recording, catalogue: catalogue)
                }
            } catch {
                guard token == generation, active else { return }
                deletionError = .context("recordingDeleteFailed", .wrapping(error))
            }
        }
    }

    private func finishDeletion(_ recording: SavedRecording, catalogue: [SavedRecording]) {
        if selected?.id == recording.id { stopPlayback(); playbackError = nil }
        didDelete?(recording.id)
        updateItems(catalogue)
        error = nil
    }

    func select(_ recording: SavedRecording?) {
        guard active else { return }
        if let recording, !items.contains(where: { $0.id == recording.id }) { return }
        guard selected?.id != recording?.id else { return }
        stopPlayback()
        playback.setMuted(true); muted = true
        playbackError = nil
        selected = recording
        loadCommercials()
    }

    func play(_ recording: SavedRecording, fromBeginning: Bool = false) async {
        guard active, let api, recording.canPlay, deletingID != recording.id else { return }
        checkpointProgress(force: true)
        progressSession = nil
        playRequest = UUID()
        let request = playRequest, token = generation
        if selected?.id != recording.id { clearCommercials() }
        commercialSkip = CommercialSkipState()
        selected = recording; playbackError = nil; opening = true
        loadCommercials()
        playbackRequested = true
        playback.stop()
        defer { if request == playRequest, token == generation { opening = false } }
        do {
            // Flush a previous session of this same recording before fetching
            // its resume point. A pending local checkpoint also works offline.
            await progressSync.flush()
            let progressRevision = progressSync.revision
            if let fresh = try? await api.recordingProgress(uuid: recording.id), request == playRequest, token == generation {
                progressSync.accept(fresh, uuid: recording.id, since: progressRevision)
                var updated = recording
                updated.playposition = fresh.playposition; updated.playcount = fresh.playcount; updated.watched = fresh.watched
                selected = updated
            }
            guard request == playRequest, token == generation, active else { return }
            let url = try await api.recordingTicketURL(for: recording)
            guard request == playRequest, token == generation, active, !Task.isCancelled else { return }
            muted = false
            playback.setMuted(false)
            let progress = progressSync.state(for: selected ?? recording)
            progressSession = RecordingProgressSession(uuid: recording.id, running: recording.isRunning, fromBeginning: fromBeginning)
            playback.start(url: url, key: "recording/\(recording.id)", resumeAt: fromBeginning ? 0 : Double(progress.position))
        } catch {
            guard request == playRequest, token == generation, !Task.isCancelled else { return }
            playbackError = .context("recordingPlaybackFailed", .wrapping(error))
        }
    }

    func stopPlayback() {
        clearCommercials()
        checkpointProgress(force: true); progressSession = nil
        playRequest = UUID(); opening = false; selected = nil
        playbackRequested = false
        playback.stop()
    }

    func toggleMute() {
        guard selected != nil, playbackRequested else { return }
        muted.toggle(); playback.setMuted(muted)
    }

    func togglePause() {
        guard let selected, selected.canPlay, !opening else { return }
        if !playbackRequested || playback.ended || playback.failed || playbackError != nil { Task { await play(selected) } }
        else { playback.togglePaused(); checkpointProgress(force: true) }
    }

    func updatePlayback() async {
        let request = playRequest
        await playback.updateTimeline(fallbackDuration: commercialFileDuration ?? selected?.recordedDuration ?? 0)
        guard request == playRequest else { return }
        if commercialPreferences.automatic, commercialsError == nil, !commercialsLoading, !timelineEditing,
           playbackRequested, !opening, playback.isPlaying, !playback.isPaused,
           !playback.ended, !playback.failed, !playback.restoringPosition, !playback.resumeFailed, playback.canSeek,
           let target = commercialSkip.target(position: playback.positionSeconds, duration: playback.durationSeconds,
                                              breaks: commercialBreaks, automatic: true) {
            playback.seek(to: target)
            checkpointProgress(force: true)
        }
        checkpointProgress(force: false)
        progressSync.retry()
    }

    private func checkpointProgress(force: Bool) {
        guard let selected, !opening, progressSession?.uuid == selected.id else { return }
        let sample = RecordingPlaybackSample(position: playback.positionSeconds, duration: playback.durationSeconds,
            playing: playback.isPlaying, paused: playback.isPaused, ended: playback.ended, failed: playback.failed,
            restoring: playback.restoringPosition || playback.resumeFailed)
        if let checkpoint = progressSession?.checkpoint(sample, force: force) { progressSync.enqueue(checkpoint, for: selected, force: force) }
    }

    func retryProgressSync() async { await progressSync.flush() }

    func seekPlayback(to seconds: Double) {
        guard playback.canSeek else { return }
        commercialSkip.userSeek(to: seconds, breaks: commercialBreaks)
        playback.seek(to: seconds)
        if seconds < 1 { progressSession?.fromBeginning = true }
    }

    func savePlaybackPosition() { checkpointProgress(force: true) }
    func setTimelineEditing(_ editing: Bool) { timelineEditing = editing }

    var canSkipCommercial: Bool {
        playbackRequested && !opening && commercialsError == nil && !commercialsLoading &&
            playback.canSeek && !playback.restoringPosition &&
            commercialBreaks.contains { $0.contains(playback.positionSeconds) }
    }

    func skipCommercial() {
        guard canSkipCommercial,
              let target = commercialSkip.target(position: playback.positionSeconds, duration: playback.durationSeconds,
                                                 breaks: commercialBreaks, automatic: false) else { return }
        playback.seek(to: target)
        checkpointProgress(force: true)
    }

    private func clearCommercials() {
        commercialsTask?.cancel(); commercialsTask = nil
        commercialsRequest = UUID(); commercialsChecked = .distantPast
        if !commercialBreaks.isEmpty { commercialBreaks = [] }
        if commercialFileDuration != nil { commercialFileDuration = nil }
        commercialsLoading = false; commercialsError = nil
        commercialSkip = CommercialSkipState()
        timelineEditing = false
    }

    /// A single metadata sync supplies all file clocks; never open each video
    /// just to measure it. Keep the normal three-second HTTP refresh responsive.
    @discardableResult func loadFileDurations(force: Bool = false) -> Task<Void, Never>? {
        guard active, let api, !items.isEmpty else { return nil }
        let connection = (api as? API)?.connection ?? Connection(address: "http://localhost:9981", username: "", password: "")
        guard let endpoint = try? commercialPreferences.endpoint(for: connection) else { return nil }
        let changedEndpoint = endpoint != fileDurationsEndpoint
        guard force || changedEndpoint || (fileDurationsTask == nil && Date().timeIntervalSince(fileDurationsChecked) >= 60) else { return nil }
        fileDurationsTask?.cancel()
        fileDurationsRequest = UUID()
        let request = fileDurationsRequest, token = generation, recordings = items
        fileDurationsEndpoint = endpoint
        let task = Task {
            do {
                let values = try await api.recordingFileDurations(for: recordings, endpoint: endpoint)
                guard !Task.isCancelled, token == generation, request == fileDurationsRequest else { return }
                applyFileDurations(values)
            } catch {
                // Missing HTSP access must not prevent browsing HTTP recordings.
            }
            guard token == generation, request == fileDurationsRequest else { return }
            fileDurationsChecked = Date(); fileDurationsTask = nil
        }
        fileDurationsTask = task
        return task
    }

    private func applyFileDurations(_ values: [String: Double]) {
        let ids = Set(items.map(\.id))
        let valid = values.filter { ids.contains($0.key) && $0.value.isFinite && $0.value > 0 }
        guard valid.contains(where: { fileDurations[$0.key] != $0.value }) else { return }
        fileDurations.merge(valid) { _, fresh in fresh }
        listCache.invalidate()
        items = items.map { original in
            var item = original
            item.fileDuration = fileDurations[item.id] ?? item.fileDuration
            return item
        }
        if let id = selected?.id { selected = items.first { $0.id == id } }
    }

    @discardableResult func loadCommercials(force: Bool = false) -> Task<Void, Never>? {
        guard active, let api, let selected, selected.canPlay,
              force || (!commercialsLoading && Date().timeIntervalSince(commercialsChecked) >= 60) else { return nil }
        commercialsTask?.cancel()
        commercialsRequest = UUID()
        let request = commercialsRequest, token = generation
        commercialsLoading = true; commercialsError = nil
        if force && !commercialBreaks.isEmpty { commercialBreaks = [] }
        let connection = (api as? API)?.connection ?? Connection(address: "http://localhost:9981", username: "", password: "")
        let endpoint: CommercialEndpoint
        do { endpoint = try commercialPreferences.endpoint(for: connection) }
        catch {
            commercialsLoading = false; commercialsError = .wrapping(error); return nil
        }
        let task = Task {
            do {
                let values = try await api.commercialData(for: selected, endpoint: endpoint)
                guard !Task.isCancelled, token == generation, request == commercialsRequest,
                      self.selected?.id == selected.id else { return }
                let breaks = CommercialBreak.normalized(values.breaks)
                let duration = values.fileDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                if commercialBreaks != breaks { commercialBreaks = breaks }
                if commercialFileDuration != duration { commercialFileDuration = duration }
                if let commercialFileDuration { applyFileDurations([selected.id: commercialFileDuration]) }
            } catch {
                guard !Task.isCancelled, token == generation, request == commercialsRequest,
                      self.selected?.id == selected.id else { return }
                commercialsError = .wrapping(error)
            }
            guard request == commercialsRequest, token == generation else { return }
            commercialsLoading = false; commercialsChecked = Date()
            commercialsTask = nil
        }
        commercialsTask = task
        return task
    }

    func prepareForTermination() async {
        await updatePlayback()
        checkpointProgress(force: true)
        progressSession = nil
        await progressSync.flush()
    }
}
