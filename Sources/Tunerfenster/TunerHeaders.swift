import Foundation

struct TunerPresentation {
    let headers: [String: String]
    let following: [String: [Preview]]
}

enum TunerHeaders {
    /// Follow each physical input through a header swap. A manually displayed
    /// service already represents that service's external viewers on the same
    /// input; it must not create a second automatic player or block the swap.
    static func presentation(tuners: [Tuner], manualSources: [String: [String]],
                             manualPaths: [String: String], activeIDs: Set<String>) -> TunerPresentation {
        var represented = [String: Set<String>]()
        for (tile, inputs) in manualSources {
            let uniqueInputs = Set(inputs)
            guard activeIDs.contains(tile), uniqueInputs.count == 1, let input = uniqueInputs.first,
                  let path = manualPaths[tile] else { continue }
            represented[input, default: []].insert(path)
        }
        let followingByInput = Dictionary(tuners.map { tuner in
            (tuner.id, tuner.previews.filter { !(represented[tuner.id] ?? []).contains($0.path) })
        }, uniquingKeysWith: { first, _ in first })
        var sources = manualSources.filter { activeIDs.contains($0.key) }
        for tuner in tuners where activeIDs.contains(tuner.id) && sources[tuner.id] == nil {
            if !(followingByInput[tuner.id] ?? []).isEmpty || tuner.unresolvedTV { sources[tuner.id] = [tuner.id] }
        }
        let headers = resolve(ids: tuners.map(\.id), sources: sources)
        let following = Dictionary(tuners.map { tuner in
            (tuner.id, followingByInput[headers[tuner.id] ?? tuner.id] ?? [])
        }, uniquingKeysWith: { first, _ in first })
        return TunerPresentation(headers: headers, following: following)
    }

    /// A presentation-only permutation. Playback and saved choices retain their
    /// original tile IDs, even when TVHeadend assigns another physical input.
    static func resolve(ids: [String], sources: [String: [String]]) -> [String: String] {
        let known = Set(ids)
        var result = Dictionary(known.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
        let sources = sources.mapValues { Array(Set($0)) }
        var neighbours = [String: Set<String>]()
        for (id, inputs) in sources where known.contains(id) {
            for input in inputs where known.contains(input) {
                neighbours[id, default: []].insert(input)
                neighbours[input, default: []].insert(id)
            }
        }

        var visited = Set<String>()
        for id in ids where !visited.contains(id) {
            var component = Set<String>(), pending = [id]
            while let next = pending.popLast() {
                guard component.insert(next).inserted else { continue }
                pending.append(contentsOf: neighbours[next] ?? [])
            }
            visited.formUnion(component)
            var assignments = [String: String]()
            var unambiguous = true
            for tile in component {
                guard let inputs = sources[tile] else { continue }
                guard inputs.count == 1, let input = inputs.first, known.contains(input) else {
                    unambiguous = false
                    break
                }
                assignments[tile] = input
            }
            // Shared or unknown reception cannot be represented by distinct
            // headers. Keep this component's names and its routing notes.
            guard unambiguous, Set(assignments.values).count == assignments.count else { continue }
            for (tile, input) in assignments { result[tile] = input }
            let assigned = Set(assignments.values)
            for start in component where !assigned.contains(start) {
                var end = start
                while let next = assignments[end] { end = next }
                result[end] = start
            }
        }
        return result
    }
}
