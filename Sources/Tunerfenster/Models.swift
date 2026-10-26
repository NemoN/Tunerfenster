import Foundation

let previewClient = "Tunerfenster/1.0"

struct Input: Decodable, Identifiable, Sendable {
    let uuid: String
    let input: String
    var stream: String? = nil
    var subs: Int? = nil
    var signal: Double? = nil
    var signal_scale: Int? = nil
    var snr: Double? = nil
    var snr_scale: Int? = nil
    var bps: Double? = nil
    var cc: Int? = nil
    // status/inputs uses a mux-instance UUID while tuned, not the frontend UUID.
    // The full input name stays stable when a tuner changes transponder.
    var id: String { input }

    var shortName: String {
        if input.hasPrefix("MaxLinear"), let number = input.range(of: #"#\d+"#, options: .regularExpression) {
            return "DVB-S2 \(input[number])"
        }
        if input.hasPrefix("Panasonic"), let number = input.range(of: #"#\d+"#, options: .regularExpression) {
            return "DVB-C \(input[number])"
        }
        return input.components(separatedBy: " (").first ?? input
    }

    var tunerNumber: String? {
        let name = shortName
        return name.range(of: #"#\d+"#, options: .regularExpression).map { String(name[$0]) }
    }

    var signalLabel: String {
        switch signal_scale {
        case 1: return "Signal \(Int(max(0, min(100, (signal ?? 0) / 65535 * 100)))) %"
        case 2: return L10n.text("signalDBm", L10n.decimal((signal ?? 0) / 1000))
        default: return "Signal –"
        }
    }

    var compactSignal: String {
        switch signal_scale {
        case 1: return "\(Int(max(0, min(100, (signal ?? 0) / 65535 * 100)))) %"
        case 2: return "\(L10n.decimal((signal ?? 0) / 1000)) dBm"
        default: return "–"
        }
    }

    var snrLabel: String? {
        switch snr_scale {
        case 1: return "SNR \(Int(max(0, min(100, (snr ?? 0) / 65535 * 100)))) %"
        case 2: return L10n.text("snrDB", L10n.decimal((snr ?? 0) / 1000))
        default: return nil
        }
    }
}

struct Subscription: Decodable, Identifiable, Sendable {
    let id: Int
    var channel: String? = nil
    var service: String? = nil
    var title: String? = nil
    var client: String? = nil
    var state: String? = nil
    var start: TimeInterval? = nil

    var isPreview: Bool { (client ?? "").hasPrefix("Tunerfenster/") }
    var isEPG: Bool {
        (title ?? "").lowercased().contains("epggrab") ||
        (service ?? "").hasSuffix("/Raw PID Subscription")
    }
}

struct Service: Decodable, Sendable {
    let uuid: String
    var network: String? = nil
    var multiplex: String? = nil
    var svcname: String? = nil
    var enabled: Bool? = nil
    var multiplex_uuid: String? = nil
    var encrypted: Bool? = nil

    var path: String { [network ?? "", multiplex ?? "", svcname ?? ""].joined(separator: "/") }
}

struct Channel: Decodable, Sendable {
    let uuid: String
    let name: String
    var enabled: Bool? = nil
    var services: [String]? = nil
    var icon_public_url: String? = nil
}

struct GridResponse<T: Decodable>: Decodable {
    let entries: [T]
    let total: Int?
    let totalCount: Int?
}

struct Preview: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let path: String
    let sourceState: String
    var encrypted: Bool = false
}

struct Multiplex: Decodable, Identifiable, Sendable {
    let uuid: String
    var network: String? = nil
    var name: String? = nil
    var delsys: String? = nil
    var frequency: Double? = nil
    var polarisation: String? = nil
    var symbolrate: Double? = nil
    var modulation: String? = nil
    var fec: String? = nil
    var orbital: String? = nil
    var satellite: Bool? = nil
    var id: String { uuid }
    var isSatellite: Bool { satellite ?? (delsys ?? "").hasPrefix("DVB-S") }
    var frequencyMHz: Double? { frequency.map { $0 / (isSatellite ? 1_000 : 1_000_000) } }
    var frequencyLabel: String? { frequencyMHz.map { "\(Self.number($0)) MHz" } }
    func band(switchMHz: Double) -> String? {
        guard isSatellite, let frequencyMHz else { return nil }
        return frequencyMHz >= switchMHz ? "HIGH" : "LOW"
    }
    func summary(switchMHz: Double) -> String {
        [frequencyLabel, isSatellite ? polarisation : nil, band(switchMHz: switchMHz)].compactMap { $0 }.joined(separator: " · ")
    }
    static func number(_ value: Double) -> String {
        let format = NumberFormatter()
        format.locale = L10n.language.locale
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = 3
        format.usesGroupingSeparator = false
        return format.string(from: NSNumber(value: value)) ?? String(value)
    }
}

struct StreamChoice: Identifiable, Sendable {
    let service: Service
    let name: String
    let mapped: Bool
    let multiplex: Multiplex?
    var id: String { service.uuid }
    var preview: Preview { Preview(id: -1, title: name, path: "stream/service/\(id)", sourceState: "", encrypted: service.encrypted == true) }

    static func catalog(services: [Service], channels: [Channel], multiplexes: [Multiplex]) -> [StreamChoice] {
        let muxes = Dictionary(multiplexes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var names = [String: String]()
        for channel in channels where channel.enabled != false {
            for id in channel.services ?? [] { names[id] = channel.name }
        }
        return services.filter { $0.enabled != false && !(names[$0.uuid] ?? $0.svcname ?? "").isEmpty }.map {
            StreamChoice(service: $0, name: names[$0.uuid] ?? $0.svcname ?? "TV", mapped: names[$0.uuid] != nil, multiplex: muxes[$0.multiplex_uuid ?? ""])
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.service.path < $1.service.path : order == .orderedAscending
        }
    }

    func matches(input: Input) -> Bool {
        guard let system = multiplex?.delsys else { return true }
        if input.input.contains("DVB-C") { return system.hasPrefix("DVB-C") }
        if input.input.contains("DVB-S") || input.input.contains("GSS.box") { return system.hasPrefix("DVB-S") }
        if input.input.contains("DVB-T") { return system.hasPrefix("DVB-T") }
        return true
    }

    static func current(for preview: Preview?, input: Input, choices: [StreamChoice], channels: [Channel]) -> StreamChoice? {
        guard let preview else { return nil }
        let compatible = choices.filter { $0.matches(input: input) }
        if let exact = compatible.first(where: { $0.preview.path == preview.path }) { return exact }
        guard let channel = channels.first(where: { "stream/channel/\($0.uuid)" == preview.path }) else { return nil }
        return compatible.first { channel.services?.contains($0.id) == true }
    }

    static func adjacent(to currentID: String?, direction: Int, input: Input, choices: [StreamChoice]) -> StreamChoice? {
        let items = choices.filter { $0.mapped && $0.matches(input: input) }
        guard !items.isEmpty, direction != 0 else { return nil }
        guard let index = items.firstIndex(where: { $0.id == currentID }) else { return direction > 0 ? items.first : items.last }
        return items[(index + (direction > 0 ? 1 : -1) + items.count) % items.count]
    }
}

struct Tuner: Identifiable, Sendable {
    let input: Input
    let previews: [Preview]
    let hasEPG: Bool
    let unresolvedTV: Bool
    var hasOwnPreview: Bool = false
    var id: String { input.id }
}

enum Snapshot {
    static func multiplex(for input: Input, multiplexes: [Multiplex]) -> Multiplex? {
        guard let stream = input.stream else { return nil }
        let matches = multiplexes.filter { "\($0.name ?? "") in \($0.network ?? "")" == stream }
        if matches.count == 1 { return matches.first }
        // Duplicate mux names exist in real catalogs. Show only values shared
        // by every candidate; never guess which delivery system is locked.
        guard matches.count > 1, let first = matches.first,
              matches.allSatisfy({ $0.isSatellite == first.isSatellite }) else { return nil }
        func common<T: Equatable>(_ key: KeyPath<Multiplex, T?>) -> T? {
            let value = first[keyPath: key]
            return matches.allSatisfy { $0[keyPath: key] == value } ? value : nil
        }
        guard let frequency = common(\.frequency) else { return nil }
        return Multiplex(uuid: "shared:" + input.id, network: first.network, name: first.name,
                         delsys: common(\.delsys), frequency: frequency, polarisation: common(\.polarisation),
                         symbolrate: common(\.symbolrate), modulation: common(\.modulation),
                         fec: common(\.fec), orbital: common(\.orbital), satellite: first.isSatellite)
    }

    static func sources(for service: Service, inputs: [Input], subscriptions: [Subscription]) -> [Input] {
        inputs.filter { input in
            subscriptions.contains { $0.isPreview && $0.service == input.input + "/" + service.path }
        }
    }

    static func tuners(inputs: [Input], subscriptions: [Subscription], services: [Service], channels: [Channel]) -> [Tuner] {
        let serviceIndex = Dictionary(services.filter { $0.enabled != false }.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return inputs.sorted { $0.input.localizedStandardCompare($1.input) == .orderedAscending }.map { input in
            // The full adapter name can itself contain slashes (DVB-S/S2).
            let prefix = input.input + "/"
            let external = subscriptions.filter { !$0.isPreview && ($0.service ?? "").hasPrefix(prefix) }
            let tv = external.filter { !$0.isEPG }
            let previews: [Preview] = tv.sorted { $0.id < $1.id }.compactMap { sub in
                let servicePath = String((sub.service ?? "").dropFirst(prefix.count))
                if let service = serviceIndex[servicePath] {
                    return Preview(id: sub.id, title: sub.channel ?? service.svcname ?? "TV", path: "stream/service/\(service.uuid)", sourceState: sub.state ?? "", encrypted: service.encrypted == true)
                }
                // Fallback for restricted service APIs, only if the channel is unambiguous.
                let matches = channels.filter { $0.enabled != false && $0.name == sub.channel }
                if matches.count == 1, let channel = matches.first {
                    return Preview(id: sub.id, title: channel.name, path: "stream/channel/\(channel.uuid)", sourceState: sub.state ?? "")
                }
                return nil
            }
            return Tuner(input: input, previews: previews, hasEPG: external.contains { $0.isEPG }, unresolvedTV: previews.isEmpty && !tv.isEmpty,
                         hasOwnPreview: subscriptions.contains { $0.isPreview && ($0.service ?? "").hasPrefix(prefix) })
        }
    }
}

struct GridFit {
    let columns: Int
    let rows: Int
    let width: Double
    let height: Double

    static func groupedRows(counts: [Int], columns: Int) -> Int {
        guard columns > 0 else { return 0 }
        return counts.reduce(0) { $0 + ($1 > 0 ? ($1 + columns - 1) / columns : 0) }
    }

    static func canFitGroups(counts: [Int], width: Double, height: Double, columns: Int) -> Bool {
        let maximum = counts.max() ?? 0
        guard maximum > 0, columns > 0 else { return false }
        let columns = min(columns, maximum)
        let rows = groupedRows(counts: counts, columns: columns)
        let available = height - Double(counts.count) * 40 - Double(max(0, counts.count - 1)) * 8
        let cellW = (width - Double(columns - 1) * 10) / Double(columns)
        let cellH = (available - Double(max(0, rows - counts.filter { $0 > 0 }.count)) * 10) / Double(rows)
        return cellW >= 112 && cellH >= 90
    }

    static func calculateGroups(counts: [Int], width: Double, height: Double, preferredColumns: Int = 0) -> GridFit {
        let maximum = counts.max() ?? 0
        guard maximum > 0 else { return GridFit(columns: 1, rows: 0, width: max(0, width), height: 0) }
        let choices = canFitGroups(counts: counts, width: width, height: height, columns: preferredColumns)
            ? [min(maximum, preferredColumns)] : Array(1...maximum)
        var best = GridFit(columns: 1, rows: 0, width: 0, height: 0), bestArea = -1.0
        for columns in choices {
            let rows = groupedRows(counts: counts, columns: columns)
            let available = height - Double(counts.count) * 40 - Double(max(0, counts.count - 1)) * 8
            let cellW = max(0, (width - Double(columns - 1) * 10) / Double(columns))
            let cellH = max(0, (available - Double(max(0, rows - counts.filter { $0 > 0 }.count)) * 10) / Double(rows))
            let videoH = max(0, min(cellH - 52, cellW * 9 / 16))
            let area = videoH * videoH * 16 / 9
            if area > bestArea { bestArea = area; best = GridFit(columns: columns, rows: rows, width: cellW, height: cellH) }
        }
        return best
    }

    static func canFit(count: Int, width: Double, height: Double, columns: Int) -> Bool {
        guard count > 0, columns > 0 else { return false }
        let columns = min(columns, count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellW = (width - Double(columns - 1) * 10) / Double(columns)
        let cellH = (height - Double(rows - 1) * 10) / Double(rows)
        return cellW >= 112 && cellH >= 90
    }

    static func calculate(count: Int, width: Double, height: Double, preferredColumns: Int = 0) -> GridFit {
        guard count > 0 else { return GridFit(columns: 1, rows: 1, width: max(0, width), height: max(0, height)) }
        let gap = 10.0
        let chrome = 52.0
        var best = GridFit(columns: 1, rows: count, width: 0, height: 0)
        var bestArea = -1.0
        let manualFits = canFit(count: count, width: width, height: height, columns: preferredColumns)
        let choices = manualFits ? [min(count, preferredColumns)] : Array(1...count)
        for columns in choices {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let cellW = max(0, (width - Double(columns - 1) * gap) / Double(columns))
            let cellH = max(0, (height - Double(rows - 1) * gap) / Double(rows))
            let videoH = max(0, min(cellH - chrome, cellW * 9 / 16))
            let area = videoH * videoH * 16 / 9
            if area > bestArea {
                bestArea = area
                best = GridFit(columns: columns, rows: rows, width: cellW, height: cellH)
            }
        }
        return best
    }
}
