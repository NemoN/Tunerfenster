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
    var id: String { uuid }
    var name: String { text(disp_title) ?? title?.localized ?? L10n.text("untitledRecording") }
    var detail: String? { text(disp_description) ?? description?.localized ?? text(disp_summary) ?? summary?.localized }
    var subtitleText: String? { text(disp_subtitle) ?? subtitle?.localized }
    var isRunning: Bool { ["recording", "recordingError"].contains(sched_status ?? "") }
    var isExisting: Bool { !uuid.isEmpty && (isRunning || (sched_status ?? "").hasPrefix("completed") || (filesize ?? 0) > 0) }
    var canPlay: Bool { isExisting && filesize != 0 && (text(url) != nil || (filesize ?? 0) > 0) }
    var hasError: Bool { ["recordingError", "completedError", "completedWarning"].contains(sched_status ?? "") }
    var statusLabel: String {
        L10n.text(!canPlay ? "recordingFileUnavailable" : isRunning ? "recordingInProgress" : hasError ? "recordingWithErrors" : "recordingCompleted")
    }
    var dateLabel: String? {
        start.map { Date(timeIntervalSince1970: $0).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.language.locale)) }
    }
    var recordedDuration: Double {
        let value = duration ?? ((stop ?? 0) - (start ?? 0))
        return value.isFinite ? max(0, value) : 0
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
    func recordingTicketURL(for recording: SavedRecording) async throws -> URL
}

extension API: RecordingLibraryAPI {
    func savedRecordings() async throws -> [SavedRecording] { try await all("dvr/entry/grid") }

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
    @Published private(set) var selected: SavedRecording?
    @Published private(set) var loading = false
    @Published private(set) var configured = false
    @Published private(set) var opening = false
    @Published private(set) var error: AppError?
    @Published private(set) var playbackError: AppError?
    @Published private(set) var muted = true
    let playback = Playback()
    private var api: (any RecordingLibraryAPI)?
    private var active = false
    private var generation = UUID()
    private var playRequest = UUID()

    func configure(_ api: (any RecordingLibraryAPI)?) {
        setActive(false)
        self.api = api
        configured = api != nil
        items = []; error = nil
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        generation = UUID(); playRequest = UUID()
        loading = false; opening = false
        if value { Task { await refresh() } }
        else {
            selected = nil; playbackError = nil
            playback.setMuted(true); playback.stop(); muted = true
        }
    }

    func refresh() async {
        guard active, let api, !loading else { return }
        loading = true
        let token = generation
        defer { if token == generation { loading = false } }
        do {
            let result = try await api.savedRecordings()
            guard token == generation, !Task.isCancelled else { return }
            // The grid also contains future timers. Keep recorded files and
            // recordings in progress, including partial files with errors.
            items = Dictionary(result.filter(\.isExisting).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
                .sorted { ($0.start ?? 0) == ($1.start ?? 0) ? $0.id < $1.id : ($0.start ?? 0) > ($1.start ?? 0) }
            error = nil
            if let selected {
                if let fresh = items.first(where: { $0.id == selected.id }), fresh.canPlay { self.selected = fresh }
                else {
                    stopPlayback()
                    playbackError = .message("recordingFileUnavailable")
                }
            }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            self.error = .context("recordingsUnavailable", .wrapping(error))
        }
    }

    func play(_ recording: SavedRecording) async {
        guard active, let api, recording.canPlay else { return }
        playRequest = UUID()
        let request = playRequest, token = generation
        selected = recording; playbackError = nil; opening = true
        playback.stop()
        defer { if request == playRequest, token == generation { opening = false } }
        do {
            let url = try await api.recordingTicketURL(for: recording)
            guard request == playRequest, token == generation, active, !Task.isCancelled else { return }
            muted = false
            playback.setMuted(false)
            playback.start(url: url, key: "recording/\(recording.id)")
        } catch {
            guard request == playRequest, token == generation, !Task.isCancelled else { return }
            playbackError = .context("recordingPlaybackFailed", .wrapping(error))
        }
    }

    func stopPlayback() {
        playRequest = UUID(); opening = false; selected = nil
        playback.stop()
    }

    func toggleMute() {
        guard selected != nil else { return }
        muted.toggle(); playback.setMuted(muted)
    }

    func togglePause() {
        guard let selected, !opening else { return }
        if playback.ended || playback.failed || playbackError != nil { Task { await play(selected) } }
        else { playback.togglePaused() }
    }
}
