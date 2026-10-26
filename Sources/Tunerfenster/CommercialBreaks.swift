import Foundation
import Combine

struct CommercialBreak: Hashable, Sendable {
    let start: Double
    let end: Double

    func contains(_ position: Double) -> Bool { position.isFinite && position >= start && position < end }

    func fractions(duration: Double) -> ClosedRange<Double>? {
        guard start.isFinite, end.isFinite, start >= 0, end > start,
              duration.isFinite, duration > 0, start < duration else { return nil }
        return max(0, start / duration)...min(1, end / duration)
    }

    static func normalized(_ values: [CommercialBreak]) -> [CommercialBreak] {
        let sorted = values.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }
            .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result = [CommercialBreak]()
        for value in sorted {
            if let last = result.last, value.start <= last.end {
                result[result.count - 1] = CommercialBreak(start: last.start, end: max(last.end, value.end))
            } else { result.append(value) }
        }
        return result
    }
}

struct CommercialSkipState {
    private var skipped = Set<CommercialBreak>()

    mutating func userSeek(to position: Double, breaks: [CommercialBreak]) {
        // Seeking back into a skipped break lets the viewer watch it.
        if let item = breaks.first(where: { $0.contains(position) }) { skipped.insert(item) }
    }

    mutating func target(position: Double, duration: Double, breaks: [CommercialBreak], automatic: Bool) -> Double? {
        guard position.isFinite, duration.isFinite, duration > 0,
              let item = breaks.first(where: { $0.contains(position) }),
              !automatic || !skipped.contains(item) else { return nil }
        let target = min(duration, item.end)
        guard target > position else { return nil }
        skipped.insert(item)
        return target
    }
}

struct CommercialEndpoint: Equatable, Sendable {
    let host: String
    let port: UInt16
}

struct RecordingCommercialData: Sendable {
    var breaks: [CommercialBreak] = []
    var fileDuration: Double? = nil
}

@MainActor final class CommercialPreferences: ObservableObject {
    static let shared = CommercialPreferences()
    private let defaults: UserDefaults
    @Published var automatic: Bool { didSet { defaults.set(automatic, forKey: "commercialAutoSkip") } }
    @Published var host: String { didSet { defaults.set(host, forKey: "commercialHTSPHost") } }
    @Published var port: Int { didSet { defaults.set(port, forKey: "commercialHTSPPort") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automatic = defaults.bool(forKey: "commercialAutoSkip")
        host = defaults.string(forKey: "commercialHTSPHost") ?? ""
        let stored = defaults.integer(forKey: "commercialHTSPPort")
        port = (1...65535).contains(stored) ? stored : 9982
    }

    func endpoint(for connection: Connection) throws -> CommercialEndpoint {
        let override = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = override.isEmpty ? connection.baseURL?.host : override,
              !host.isEmpty, !host.contains(where: { $0.isWhitespace || "/?#@".contains($0) }),
              let port = UInt16(exactly: port), port > 0 else { throw AppError.message("commercialEndpointInvalid") }
        return CommercialEndpoint(host: host, port: port)
    }
}
