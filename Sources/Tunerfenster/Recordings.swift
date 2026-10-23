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
    @Published private(set) var errors = [String: AppError]()
    private var api: (any RecordingAPI)?
    private var generation = UUID()
    private var lastCheck = Date.distantPast
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
        pending = []; submitted = []; stopped = []; errors = [:]; lastCheck = .distantPast
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
        return api != nil && profile != nil && event.isCurrent(at: now()) && event.id > 0 &&
            !event.hasRecording && !pending.contains(key) && !submitted.contains(key)
    }

    func isRecording(_ event: Programme) -> Bool {
        event.recordingIsRunning && !stopped.contains(event.dvrUuid ?? "")
    }

    func canStop(_ event: Programme) -> Bool {
        api != nil && isRecording(event) && !pending.contains(Self.key(event))
    }

    func stop(_ event: Programme) async {
        guard canStop(event), let api, let uuid = event.dvrUuid else { return }
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
            if entry.isRunning {
                try await api.stopRecording(uuid: uuid)
                guard token == generation else { return }
                let result = try await api.recordingStatus(uuid: uuid)
                guard token == generation else { return }
                guard let result, result.matches(event), !result.isRunning else {
                    throw AppError.message("recordingStillRunning")
                }
            }
            stopped.insert(uuid)
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
            if fresh.hasRecording { submitted.insert(key); return }
            _ = try await api.recordProgramme(eventID: fresh.id, profileID: profile.uuid)
            guard token == generation else { return }
            submitted.insert(key)
        } catch {
            guard token == generation else { return }
            errors[key] = .context("recordingFailed", .wrapping(error))
        }
    }
}
