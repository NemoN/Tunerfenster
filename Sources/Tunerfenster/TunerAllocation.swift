import Foundation

struct TunerAllocation {
    let assignments: [String: StreamChoice]
    let targetCount: Int

    /// Services on the same carrier can share one physical tuner, even when
    /// TVHeadend has duplicate mux records or different DVB-S/S2 descriptions.
    static func carrierKey(for choice: StreamChoice) -> String? {
        guard let mux = choice.multiplex, let frequency = mux.frequencyMHz,
              frequency.isFinite, frequency > 0, let system = mux.delsys else { return nil }
        let family: String
        if system.hasPrefix("DVB-S") { family = "satellite" }
        else if system.hasPrefix("DVB-C") { family = "cable" }
        else if system.hasPrefix("DVB-T") { family = "terrestrial" }
        else { return nil }
        let network = mux.network ?? choice.service.network ?? ""
        let source = family == "satellite" ? (mux.orbital ?? network) : network
        return [family, source, String((frequency * 1_000).rounded()),
                family == "satellite" ? (mux.polarisation ?? "").uppercased() : ""].joined(separator: "\n")
    }

    static func plan(tuners: [Tuner], choices: [StreamChoice], current: [String: StreamChoice]) -> TunerAllocation {
        let eligible = choices.filter { $0.mapped && carrierKey(for: $0) != nil }
        var candidates = [String: [StreamChoice]]()
        for tuner in tuners {
            var seen = Set<String>()
            let preferred = current[tuner.id].flatMap { item in eligible.first { $0.id == item.id } }
            let orderedChoices = (preferred.map { [$0] } ?? []) + eligible
            candidates[tuner.id] = orderedChoices.filter { choice in
                guard choice.matches(input: tuner.input), let key = carrierKey(for: choice) else { return false }
                return seen.insert(key).inserted
            }
        }

        var assignments = [String: StreamChoice]()
        var owners = [String: String]()
        let ordered = tuners.sorted {
            let a = candidates[$0.id]?.count ?? 0, b = candidates[$1.id]?.count ?? 0
            return a == b ? $0.id < $1.id : a < b
        }
        // Keep existing distinct carriers before filling spare tiles.
        for tuner in ordered {
            if let choice = current[tuner.id], let candidate = candidates[tuner.id]?.first,
               candidate.id == choice.id, let key = carrierKey(for: candidate), owners[key] == nil {
                owners[key] = tuner.id; assignments[tuner.id] = candidate
            }
        }

        func assign(_ id: String, visited: inout Set<String>) -> Bool {
            let items = candidates[id] ?? []
            for choice in items {
                guard let key = carrierKey(for: choice), owners[key] == nil,
                      visited.insert(key).inserted else { continue }
                owners[key] = id; assignments[id] = choice
                return true
            }
            // Rearrange only when a constrained input has no unused carrier.
            for choice in items {
                guard let key = carrierKey(for: choice), visited.insert(key).inserted,
                      let owner = owners[key], assign(owner, visited: &visited) else { continue }
                owners[key] = id; assignments[id] = choice
                return true
            }
            return false
        }
        for tuner in ordered where assignments[tuner.id] == nil {
            var visited = Set<String>()
            _ = assign(tuner.id, visited: &visited)
        }
        return TunerAllocation(assignments: assignments, targetCount: tuners.count)
    }
}
