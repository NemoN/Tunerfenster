import Foundation

struct Programme: Decodable, Identifiable, Equatable, Sendable {
    let eventId: Int
    let channelUuid: String
    let start: TimeInterval
    let stop: TimeInterval
    var title: String? = nil
    var subtitle: String? = nil
    var summary: String? = nil
    var description: String? = nil
    var dvrUuid: String? = nil
    var dvrState: String? = nil
    var id: Int { eventId }
    var startDate: Date { Date(timeIntervalSince1970: start) }
    var stopDate: Date { Date(timeIntervalSince1970: stop) }
    var hasRecording: Bool { !(dvrUuid ?? "").isEmpty }
    var recordingIsActive: Bool { hasRecording && dvrState == "recording" }
    var recordingIsRunning: Bool { hasRecording && ["recording", "recordingError"].contains(dvrState ?? "") }
    var recordingIsFinished: Bool { hasRecording && ["completed", "completedError", "completedWarning", "completedRerecord"].contains(dvrState ?? "") }
    var recordingHasError: Bool { hasRecording && ["recordingError", "completedError", "completedWarning"].contains(dvrState ?? "") }
    func isCurrent(at date: Date) -> Bool { start <= date.timeIntervalSince1970 && stop > date.timeIntervalSince1970 }
    var details: String? {
        [description, summary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
    func progress(at date: Date) -> Double {
        guard stop > start else { return 0 }
        return max(0, min(1, (date.timeIntervalSince1970 - start) / (stop - start)))
    }
}

struct ProgrammeSchedule: Sendable {
    let events: [Programme]

    init(events: [Programme], channelID: String) {
        // An unknown channel filter can return the entire EPG. Never show a
        // programme from a different channel, even if the API ignored its filter.
        self.events = events.filter { $0.channelUuid == channelID && $0.stop > $0.start }.sorted { $0.start < $1.start }
    }
    func current(at date: Date) -> Programme? {
        events.last { $0.start <= date.timeIntervalSince1970 && $0.stop > date.timeIntervalSince1970 }
    }
    func next(at date: Date) -> Programme? {
        let boundary = current(at: date)?.stop ?? date.timeIntervalSince1970
        return events.first { $0.start >= boundary && $0.start > date.timeIntervalSince1970 }
    }

    static func channel(for preview: Preview, channels: [Channel]) -> Channel? {
        let enabled = channels.filter { $0.enabled != false }
        if preview.path.hasPrefix("stream/channel/") {
            let uuid = String(preview.path.dropFirst("stream/channel/".count))
            return enabled.first { $0.uuid == uuid }
        }
        guard preview.path.hasPrefix("stream/service/") else { return nil }
        let uuid = String(preview.path.dropFirst("stream/service/".count))
        let matches = enabled.filter { ($0.services ?? []).contains(uuid) }
        let named = matches.filter { $0.name == preview.title }
        return named.count == 1 ? named.first : matches.count == 1 ? matches.first : nil
    }
}

extension API {
    func programmeSchedule(channelID: String, language: AppLanguage) async throws -> ProgrammeSchedule {
        let response: GridResponse<Programme> = try await read("epg/events/grid", query: [
            URLQueryItem(name: "channel", value: channelID),
            URLQueryItem(name: "lang", value: language == .german ? "deu" : "eng"),
            URLQueryItem(name: "sort", value: "start"), URLQueryItem(name: "dir", value: "ASC"),
            URLQueryItem(name: "limit", value: "12")
        ])
        return ProgrammeSchedule(events: response.entries, channelID: channelID)
    }
}
