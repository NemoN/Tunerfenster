import Foundation

enum TunerUsageKind: CaseIterable {
    case tv, recording, epg, preview, other

    var title: String {
        switch self {
        case .tv: return L10n.text("usageTV")
        case .recording: return L10n.text("usageRecording")
        case .epg: return "EPG"
        case .preview: return L10n.text("usagePreview")
        case .other: return L10n.text("usageOther")
        }
    }

    var symbol: String {
        switch self {
        case .tv: return "tv"
        case .recording: return "record.circle"
        case .epg: return "list.bullet.rectangle"
        case .preview: return "play.rectangle"
        case .other: return "questionmark.circle"
        }
    }
}

extension Subscription {
    var usageKind: TunerUsageKind {
        if isPreview { return .preview }
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // TVHeadend's recorder prefixes subscription titles with "DVR: ".
        if title.hasPrefix("DVR:") { return .recording }
        if title.contains("EPGGRAB") { return .epg }
        if isEPG { return title.isEmpty ? .epg : .other }
        if channel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            ["HTTP", "HTSP", "SAT>IP"].contains(title) { return .tv }
        return .other
    }

    func usageName(for input: Input) -> String {
        if let channel, !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return channel }
        if usageKind == .epg, let stream = input.stream, !stream.isEmpty { return stream }
        let prefix = input.input + "/"
        if let service, service.hasPrefix(prefix),
           let name = service.dropFirst(prefix.count).split(separator: "/").last { return String(name) }
        return L10n.text("usageChannelUnknown")
    }

    var usageDetail: String? {
        if usageKind == .recording {
            let programme = String((title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(4))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !programme.isEmpty { return programme }
        }
        guard !isPreview, let client, !client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return client
    }
}

struct TunerUsage: Identifiable {
    let tuner: Tuner
    let subscriptions: [Subscription]
    var id: String { tuner.id }
    var unassignedCount: Int { max(0, (tuner.input.subs ?? 0) - subscriptions.count) }
    var isRecording: Bool { subscriptions.contains { $0.usageKind == .recording } }

    static func recordingInputIDs(tuners: [Tuner], subscriptions: [Subscription]) -> Set<String> {
        Set(overview(tuners: tuners, subscriptions: subscriptions).filter(\.isRecording).map(\.id))
    }

    static func overview(tuners: [Tuner], subscriptions: [Subscription]) -> [TunerUsage] {
        var grouped = [String: [Subscription]]()
        // Prefer the longest full input name when one name is a prefix of another.
        let inputs = tuners.sorted { $0.input.input.count > $1.input.input.count }
        for subscription in subscriptions {
            guard let service = subscription.service,
                  let tuner = inputs.first(where: { service.hasPrefix($0.input.input + "/") }) else { continue }
            grouped[tuner.id, default: []].append(subscription)
        }
        return tuners.filter { ($0.input.subs ?? 0) > 0 }.map { tuner in
            TunerUsage(tuner: tuner, subscriptions: (grouped[tuner.id] ?? []).sorted { $0.id < $1.id })
        }
    }
}
