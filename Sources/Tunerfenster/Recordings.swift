import Foundation
import Combine

struct RecordingProfile: Decodable, Equatable, Sendable {
    let uuid: String
    var name: String = ""
    var enabled: Bool? = nil
    var storage: String? = nil

    var usable: Bool {
        !uuid.isEmpty && enabled != false && storage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true
    }
}

protocol RecordingAPI: Sendable {
    func recordingProfiles() async throws -> [RecordingProfile]
    func recordingEvent(_ event: Programme, language: AppLanguage) async throws -> Programme?
    func activeRecordings(for event: Programme) async throws -> [RecordingEntry]
    func recordProgramme(eventID: Int, profileID: String) async throws -> String
    func recordingStatus(uuid: String) async throws -> RecordingEntry?
    func stopRecording(uuid: String) async throws
}

struct RecordingEntry: Decodable, Sendable {
    let uuid: String
    let channel: String?
    let broadcast: Int?
    let sched_status: String?
    var isRunning: Bool { ["recording", "recordingError"].contains(sched_status ?? "") }
    var isFinished: Bool { ["completed", "completedError", "completedWarning", "completedRerecord"].contains(sched_status ?? "") }

    func refersTo(_ event: Programme) -> Bool {
        channel == event.channelUuid && (broadcast == event.id || uuid == event.dvrUuid)
    }

    func matches(_ event: Programme) -> Bool {
        uuid == event.dvrUuid && channel == event.channelUuid &&
            (broadcast == nil || broadcast == 0 || broadcast == event.id)
    }
}

private struct RecordingActionResponse: Decodable {}

struct CreatedRecording: Decodable {
    let uuid: [String]?
    var identifier: String? { uuid?.first.flatMap { $0.isEmpty ? nil : $0 } }
}

extension API: RecordingAPI {
    func recordingProfiles() async throws -> [RecordingProfile] {
        // Configurations can also be read by an admin without recorder rights.
        // This read-only probe checks the privilege needed by create_by_event.
        let _: GridResponse<RecordingPermissionProbe> = try await read("dvr/entry/grid_upcoming", query: [URLQueryItem(name: "limit", value: "1")])
        return try await all("dvr/config/grid")
    }

    func recordingEvent(_ event: Programme, language: AppLanguage) async throws -> Programme? {
        try await programmeSchedule(channelID: event.channelUuid, language: language).events.first { $0.id == event.id }
    }

    func activeRecordings(for event: Programme) async throws -> [RecordingEntry] {
        let entries: [RecordingEntry] = try await all("dvr/entry/grid_upcoming")
        return entries.filter { !$0.uuid.isEmpty && !$0.isFinished && $0.refersTo(event) }
    }

    func recordProgramme(eventID: Int, profileID: String) async throws -> String {
        let response: CreatedRecording = try await post("dvr/entry/create_by_event", form: [
            URLQueryItem(name: "event_id", value: String(eventID)),
            URLQueryItem(name: "config_uuid", value: profileID)
        ])
        // TVHeadend can return HTTP 200 without a UUID when it rejected the event.
        guard let identifier = response.identifier else { throw AppError.message("recordingRejected") }
        return identifier
    }

    func recordingStatus(uuid: String) async throws -> RecordingEntry? {
        let response: GridResponse<RecordingEntry> = try await read("idnode/load", query: [
            URLQueryItem(name: "uuid", value: uuid), URLQueryItem(name: "grid", value: "1")
        ])
        return response.entries.first { $0.uuid == uuid }
    }

    func stopRecording(uuid: String) async throws {
        // TVHeadend's graceful stop finalizes the file. Never cancel or remove it.
        let _: RecordingActionResponse = try await post("dvr/entry/stop", form: [URLQueryItem(name: "uuid", value: uuid)])
    }
}

private struct RecordingPermissionProbe: Decodable {}

@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var profiles = [RecordingProfile]()
    @Published private(set) var checking = false
    @Published private(set) var availabilityError: AppError?
    @Published private(set) var pending = Set<String>()
    @Published private(set) var submitted = Set<String>()
    @Published private(set) var stopped = Set<String>()
    @Published private(set) var entries = [String: RecordingEntry]()
    @Published private(set) var errors = [String: AppError]()
    private var api: (any RecordingAPI)?
    private var generation = UUID()
    private var lastCheck = Date.distantPast
    private var statusChecks = Set<String>()
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    var profile: RecordingProfile? {
        profiles.first { $0.name.isEmpty } ?? profiles.first
    }
    static func key(_ event: Programme) -> String { "\(event.channelUuid)/\(event.id)" }

    func configure(_ api: (any RecordingAPI)?) {
        generation = UUID()
        self.api = api
        profiles = []; checking = false; availabilityError = nil
        pending = []; submitted = []; stopped = []; entries = [:]; statusChecks = []
        errors = [:]; lastCheck = .distantPast
    }

    func refreshAvailability(force: Bool = false) async {
        guard let api, !checking, force || now().timeIntervalSince(lastCheck) >= 30 else { return }
        checking = true
        let token = generation
        do {
            let profiles = try await api.recordingProfiles()
            guard token == generation else { return }
            self.profiles = profiles.filter(\.usable).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            availabilityError = self.profiles.isEmpty ? .message("recordingNotConfigured") : nil
        } catch {
            guard token == generation else { return }
            profiles = []
            availabilityError = .context("recordingUnavailable", .wrapping(error))
        }
        checking = false
        lastCheck = now()
    }

    func canRecord(_ event: Programme) -> Bool {
        let key = Self.key(event)
        let current = recording(for: event)
        let restart = canRestart(event)
        return api != nil && profile != nil && event.isCurrent(at: now()) && event.id > 0 &&
            (!current.hasRecording || restart) && !pending.contains(key) && (!submitted.contains(key) || restart)
    }

    func recording(for event: Programme) -> Programme {
        guard let entry = entries[Self.key(event)] else { return event }
        // An active EPG entry from another client supersedes a finished cache.
        // Keep a directly confirmed active UUID when EPG still names an old file.
        if entry.isFinished, event.hasRecording, event.dvrUuid != entry.uuid, !event.recordingIsFinished,
           !stopped.contains(event.dvrUuid ?? "") { return event }
        var result = event
        result.dvrUuid = entry.uuid
        result.dvrState = entry.sched_status
        return result
    }

    func canRestart(_ event: Programme) -> Bool {
        let current = recording(for: event)
        return event.isCurrent(at: now()) && current.hasRecording &&
            (current.recordingIsFinished || stopped.contains(current.dvrUuid ?? ""))
    }

    func isRecording(_ event: Programme) -> Bool {
        let current = recording(for: event)
        return current.recordingIsRunning && !stopped.contains(current.dvrUuid ?? "")
    }

    func canStop(_ event: Programme) -> Bool {
        api != nil && isRecording(event) && !pending.contains(Self.key(event))
    }

    func forgetRecording(uuid: String) {
        let keys = entries.filter { $0.value.uuid == uuid }.map(\.key)
        for key in keys {
            entries[key] = nil
            submitted.remove(key)
            errors[key] = nil
        }
        stopped.remove(uuid)
    }

    func stop(_ event: Programme) async {
        guard canStop(event), let api, let uuid = recording(for: event).dvrUuid else { return }
        let event = recording(for: event)
        let key = Self.key(event)
        let token = generation
        pending.insert(key)
        errors[key] = nil
        defer { if token == generation { pending.remove(key) } }
        do {
            // Validate the captured UUID against the server, even if the viewer
            // switches channels or the programme ends while this request runs.
            let entry = try await api.recordingStatus(uuid: uuid)
            guard token == generation else { return }
            guard let entry, entry.matches(event) else { throw AppError.message("recordingChanged") }
            var finished = entry
            if entry.isRunning {
                try await api.stopRecording(uuid: uuid)
                guard token == generation else { return }
                let result = try await api.recordingStatus(uuid: uuid)
                guard token == generation else { return }
                guard let result, result.matches(event), result.isFinished else {
                    throw AppError.message("recordingStillRunning")
                }
                finished = result
            }
            guard finished.isFinished else { throw AppError.message("recordingStillRunning") }
            stopped.insert(uuid)
            entries[key] = finished
            submitted.remove(key)
        } catch {
            guard token == generation else { return }
            errors[key] = .context("recordingStopFailed", .wrapping(error))
        }
    }

    func record(_ event: Programme) async {
        guard canRecord(event), let api, let profile else { return }
        let key = Self.key(event)
        let token = generation
        pending.insert(key)
        errors[key] = nil
        defer { if token == generation { pending.remove(key) } }
        do {
            // Revalidate after a double click, an EPG boundary or another client's
            // recording request. Never silently record the next programme.
            let fresh = try await api.recordingEvent(event, language: L10n.language)
            guard token == generation else { return }
            guard let fresh, Self.key(fresh) == key, fresh.isCurrent(at: now()) else { throw AppError.message("recordingProgrammeEnded") }
            // EPG may still point to the old, finished UUID. Check all upcoming
            // entries before creating another file, including other clients.
            let active = try await api.activeRecordings(for: fresh)
            guard token == generation else { return }
            if let existing = active.sorted(by: {
                $0.isRunning == $1.isRunning ? $0.uuid < $1.uuid : $0.isRunning
            }).first {
                entries[key] = existing
                stopped.remove(existing.uuid)
                submitted.insert(key)
                return
            }
            let known = recording(for: fresh)
            if let uuid = known.dvrUuid, !uuid.isEmpty, !known.recordingIsFinished && !stopped.contains(uuid) {
                entries[key] = RecordingEntry(uuid: uuid, channel: known.channelUuid,
                                              broadcast: known.id, sched_status: known.dvrState)
                submitted.insert(key)
                return
            }
            guard fresh.isCurrent(at: now()) else { throw AppError.message("recordingProgrammeEnded") }
            let uuid = try await api.recordProgramme(eventID: fresh.id, profileID: profile.uuid)
            guard token == generation else { return }
            guard uuid != fresh.dvrUuid, uuid != entries[key]?.uuid, !stopped.contains(uuid) else {
                throw AppError.message("recordingRejected")
            }
            entries[key] = RecordingEntry(uuid: uuid, channel: fresh.channelUuid, broadcast: fresh.id, sched_status: "scheduled")
            submitted.insert(key)
            await refreshRecording(fresh)
        } catch {
            guard token == generation else { return }
            errors[key] = .context("recordingFailed", .wrapping(error))
        }
    }

    func refreshRecording(_ event: Programme) async {
        let key = Self.key(event)
        guard let api, let uuid = recording(for: event).dvrUuid, !statusChecks.contains(key) else { return }
        let token = generation
        statusChecks.insert(key)
        defer { if token == generation { statusChecks.remove(key) } }
        do {
            let result = try await api.recordingStatus(uuid: uuid)
            guard token == generation, !Task.isCancelled, recording(for: event).dvrUuid == uuid else { return }
            var expected = event
            expected.dvrUuid = uuid
            guard let result, result.matches(expected) else { return }
            // After relaunch, EPG can still identify the first finished file.
            // Recover a later active entry before offering another restart.
            let active = result.isFinished ? (try? await api.activeRecordings(for: event)) ?? [] : []
            guard token == generation, !Task.isCancelled, recording(for: event).dvrUuid == uuid else { return }
            if result.isFinished { stopped.insert(uuid) }
            entries[key] = active.filter { $0.uuid != uuid }.sorted {
                $0.isRunning == $1.isRunning ? $0.uuid < $1.uuid : $0.isRunning
            }.first ?? result
        } catch {
            // A successful create remains submitted if its status read fails;
            // polling retries it instead of enabling a duplicate request.
        }
    }
}
