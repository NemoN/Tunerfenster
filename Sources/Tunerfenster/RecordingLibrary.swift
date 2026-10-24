import Foundation
import Combine

struct RecordingText: Decodable, Sendable {
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

struct SavedRecording: Decodable, Identifiable, Sendable {
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
    var start: Double? = nil
    var stop: Double? = nil
    var duration: Double? = nil
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
        if let duration { value = duration }
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

protocol RecordingLibraryAPI: Sendable {
    func savedRecordings() async throws -> [SavedRecording]
    func recordingStorageRoots() async throws -> [RecordingStorage]
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL
    func deleteRecording(uuid: String) async throws
    func recordingProgress(uuid: String) async throws -> RecordingProgress
    func saveRecordingProgress(uuid: String, checkpoint: RecordingCheckpoint) async throws -> RecordingProgress
}

private struct RecordingDeletionResponse: Decodable {}

extension API: RecordingLibraryAPI {
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
    var didDelete: ((String) -> Void)?
    let playback = Playback()
    private var api: (any RecordingLibraryAPI)?
    private var active = false
    private var generation = UUID()
    private var playRequest = UUID()
    private let listCache = RecordingListCache()
    private let progressSync = RecordingProgressSync()
    private var progressSession: RecordingProgressSession?

    init() {
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
        listCache.invalidate()
        items = []; storageRoots = []; error = nil
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        if !value { checkpointProgress(force: true); progressSession = nil }
        active = value
        generation = UUID(); playRequest = UUID()
        loading = false; opening = false
        deletionCandidate = nil; deletingID = nil; deletionError = nil
        if value { Task { await refresh() } }
        else {
            selected = nil; playbackError = nil
            playbackRequested = false
            playback.setMuted(true); playback.stop(); muted = true
        }
    }

    func refresh() async {
        guard active, let api, !loading, deletingID == nil else { return }
        loading = true
        let token = generation
        let progressRevision = progressSync.revision
        defer { if token == generation { loading = false } }
        do {
            async let roots = try? api.recordingStorageRoots()
            let result = try await api.savedRecordings()
            let storage = await roots
            guard token == generation, !Task.isCancelled else { return }
            if let storage { storageRoots = storage }
            updateItems(result, progressRevision: progressRevision)
            error = nil
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            self.error = .context("recordingsUnavailable", .wrapping(error))
        }
    }

    var folderTree: RecordingFolderTree { RecordingFolderTree(items: items, storageRoots: storageRoots) }

    func listSnapshot(sort: RecordingSort, search: String) -> RecordingListSnapshot {
        listCache.snapshot(items: items, storageRoots: storageRoots, sort: sort, search: search)
    }

    private func updateItems(_ result: [SavedRecording], progressRevision: Int? = nil) {
        listCache.invalidate()
        // The grid also contains future timers. Keep recorded files and
        // recordings in progress, including partial files with errors.
        items = Dictionary(result.filter(\.isExisting).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
            .sorted { ($0.start ?? 0) == ($1.start ?? 0) ? $0.id < $1.id : ($0.start ?? 0) > ($1.start ?? 0) }
        progressSync.merge(items, since: progressRevision ?? progressSync.revision)
        if let selected {
            if let fresh = items.first(where: { $0.id == selected.id }) {
                if playbackRequested && !fresh.canPlay {
                    stopPlayback()
                    playbackError = .message("recordingFileUnavailable")
                }
                self.selected = fresh
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
    }

    func play(_ recording: SavedRecording, fromBeginning: Bool = false) async {
        guard active, let api, recording.canPlay, deletingID != recording.id else { return }
        checkpointProgress(force: true)
        progressSession = nil
        playRequest = UUID()
        let request = playRequest, token = generation
        selected = recording; playbackError = nil; opening = true
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
        await playback.updateTimeline(fallbackDuration: selected?.recordedDuration ?? 0)
        guard request == playRequest else { return }
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
        playback.seek(to: seconds)
        if seconds < 1 { progressSession?.fromBeginning = true }
    }

    func savePlaybackPosition() { checkpointProgress(force: true) }

    func prepareForTermination() async {
        await updatePlayback()
        checkpointProgress(force: true)
        progressSession = nil
        await progressSync.flush()
    }
}
