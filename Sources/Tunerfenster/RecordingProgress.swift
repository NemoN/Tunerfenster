import Foundation

struct RecordingProgress: Codable, Equatable, Sendable {
    var playposition: Double? = nil
    var playcount: Int? = nil
    var watched: Double? = nil

    var position: Int {
        guard let value = playposition, value.isFinite, value >= 0, value <= Double(UInt32.max) else { return 0 }
        return Int(value)
    }
    var seen: Bool {
        // An explicit zero is an unwatched mark. The historical timestamp can
        // remain set on servers whose JSON API exposes it as read-only.
        if let playcount { return playcount > 0 }
        return watched.map { $0.isFinite && $0 > 0 } ?? false
    }
    var symbol: String { seen ? "eye.fill" : position > 0 ? "circle.lefthalf.filled" : "circle" }
    var label: String {
        let state = L10n.text(seen ? "recordingSeen" : position > 0 ? "recordingStarted" : "recordingUnseen")
        return position > 0 ? state + " · " + L10n.text("recordingContinueAt", Self.time(position)) : state
    }
    static func time(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) :
            String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct RecordingCheckpoint: Codable, Equatable, Sendable {
    let position: Int
    let seen: Bool
    var seenOverride: Bool? = nil
    func applying(to progress: RecordingProgress) -> RecordingProgress {
        var result = progress
        result.playposition = Double(position)
        if let seenOverride { result.playcount = seenOverride ? max(1, result.playcount ?? 0) : 0 }
        else if seen { result.playcount = max(1, result.playcount ?? 0) }
        return result
    }

    func superseding(_ previous: Self?) -> Self {
        // Explicit menu actions replace earlier intent in either direction.
        // Ordinary position updates carry an unsent manual mark forward.
        if seenOverride != nil { return self }
        let carriedOverride = previous?.seenOverride.map { seen ? true : $0 }
        return .init(position: position, seen: seen || previous?.seen == true, seenOverride: carriedOverride)
    }
}

struct RecordingPlaybackSample {
    var position: Double
    var duration: Double
    var playing = false
    var paused = false
    var ended = false
    var failed = false
    var restoring = false
}

/// Tracks one playback session. Startup zeros and failed resume attempts must
/// never overwrite a stored position. Completion writes are idempotent.
struct RecordingProgressSession {
    let uuid: String
    let running: Bool
    var fromBeginning = false
    private var lastCheckpoint: RecordingCheckpoint?
    private var lastSave = Date.distantPast
    private var manualAnchor: Double?
    private var suppressCompletion = false

    mutating func markManually(seen: Bool, at position: Double, now: Date = Date()) {
        manualAnchor = position.isFinite ? position : nil
        suppressCompletion = !seen
        lastCheckpoint = .init(position: 0, seen: seen)
        lastSave = now
    }

    mutating func checkpoint(_ sample: RecordingPlaybackSample, force: Bool, now: Date = Date()) -> RecordingCheckpoint? {
        guard !sample.restoring, !sample.failed, sample.playing || sample.paused || sample.ended,
              sample.position.isFinite, sample.position >= 0, sample.position <= Double(UInt32.max) else { return nil }
        let duration = sample.duration.isFinite ? max(0, sample.duration) : 0
        if let manualAnchor {
            guard abs(sample.position - manualAnchor) >= 1 else { return nil }
            self.manualAnchor = nil
        }
        let completed = !suppressCompletion && !running && (sample.ended || duration > 0 && sample.position >= duration * 0.9)
        guard sample.position >= 1 || completed || fromBeginning else { return nil }
        let next = RecordingCheckpoint(position: completed ? 0 : Int(sample.position), seen: completed)
        guard next != lastCheckpoint, force || now.timeIntervalSince(lastSave) >= 10 else { return nil }
        lastCheckpoint = next; lastSave = now; fromBeginning = false
        return next
    }
}

/// Unsent checkpoints survive a failed request or app exit, scoped to the
/// server/account. Never persist credentials or a VLC ticket.
struct RecordingProgressOutbox {
    static let key = "recordingProgressOutboxV1"
    let defaults: UserDefaults
    private var document: [String: [String: RecordingCheckpoint]] {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode([String: [String: RecordingCheckpoint]].self, from: data) else { return [:] }
        return value
    }
    func load(scope: String) -> [String: RecordingCheckpoint] {
        (document[scope] ?? [:]).filter { Self.validUUID($0.key) && (0...Int(UInt32.max)).contains($0.value.position) }
    }
    func save(_ pending: [String: RecordingCheckpoint], scope: String) {
        var value = document
        value[scope] = pending.isEmpty ? nil : pending
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
    static func validUUID(_ uuid: String) -> Bool { uuid.count == 32 && uuid.allSatisfy(\.isHexDigit) }
}

@MainActor
final class RecordingProgressSync {
    private struct Pending { let checkpoint: RecordingCheckpoint; let revision: UUID }
    private let outbox: RecordingProgressOutbox
    private var api: (any RecordingLibraryAPI)?
    private var scope: String?
    private var generation = UUID()
    private var pending = [String: Pending]()
    private var states = [String: RecordingProgress]()
    private var worker: Task<Void, Never>?
    private var lastAttempt = Date.distantPast
    private(set) var revision = 0
    private var changedAt = [String: Int]()
    private(set) var error: AppError?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) { outbox = RecordingProgressOutbox(defaults: defaults) }

    func configure(_ api: (any RecordingLibraryAPI)?, scope: String?) {
        persist()
        worker?.cancel(); worker = nil; generation = UUID()
        self.api = api; self.scope = scope
        states = [:]; error = nil
        revision = 0; changedAt = [:]
        pending = scope.map { outbox.load(scope: $0).mapValues { Pending(checkpoint: $0, revision: UUID()) } } ?? [:]
        lastAttempt = .distantPast
    }

    func state(for recording: SavedRecording) -> RecordingProgress {
        let base = states[recording.id] ?? recording.progress
        return pending[recording.id]?.checkpoint.applying(to: base) ?? base
    }

    func merge(_ catalogue: [SavedRecording], since requestRevision: Int) {
        let previousStates = states
        let previousPending = Set(pending.keys)
        let hadError = error != nil
        let ids = Set(catalogue.map(\.id))
        pending = pending.filter { ids.contains($0.key) }
        if pending.isEmpty { error = nil }
        states = states.filter { ids.contains($0.key) }
        for recording in catalogue where (changedAt[recording.id] ?? 0) <= requestRevision {
            states[recording.id] = recording.progress
        }
        if previousPending != Set(pending.keys) { persist() }
        if previousStates != states || previousPending != Set(pending.keys) || hadError != (error != nil) { onChange?() }
        retry()
    }

    func accept(_ progress: RecordingProgress, uuid: String, since requestRevision: Int) {
        guard (changedAt[uuid] ?? 0) <= requestRevision else { return }
        states[uuid] = progress
        revision += 1; changedAt[uuid] = revision
        onChange?()
    }

    func enqueue(_ checkpoint: RecordingCheckpoint, for recording: SavedRecording, force: Bool = false) {
        guard api != nil, RecordingProgressOutbox.validUUID(recording.id) else { return }
        pending[recording.id] = Pending(checkpoint: checkpoint.superseding(pending[recording.id]?.checkpoint), revision: UUID())
        revision += 1; changedAt[recording.id] = revision
        persist(); onChange?(); retry(force: force)
    }

    func retry(force: Bool = false) {
        guard worker == nil, !pending.isEmpty, let api,
              force || Date().timeIntervalSince(lastAttempt) >= 10 else { return }
        let token = generation
        lastAttempt = Date()
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.worker = nil } }
            while let uuid = self.pending.keys.sorted().first, let request = self.pending[uuid] {
                do {
                    let progress = try await api.saveRecordingProgress(uuid: uuid, checkpoint: request.checkpoint)
                    guard self.generation == token, !Task.isCancelled else { return }
                    self.states[uuid] = progress
                    self.revision += 1; self.changedAt[uuid] = self.revision
                    if self.pending[uuid]?.revision == request.revision { self.pending.removeValue(forKey: uuid) }
                    self.error = nil
                    self.persist(); self.onChange?()
                } catch {
                    guard self.generation == token, !Task.isCancelled else { return }
                    if self.pending[uuid] == nil { continue }
                    self.error = .context("recordingProgressSaveFailed", .wrapping(error))
                    self.onChange?()
                    return
                }
            }
        }
    }

    func flush(timeout: TimeInterval = 5) async {
        retry(force: true)
        let deadline = Date().addingTimeInterval(timeout)
        while worker != nil, Date() < deadline, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
    }

    private func persist() {
        if let scope { outbox.save(pending.mapValues(\.checkpoint), scope: scope) }
    }
}
