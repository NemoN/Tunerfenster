import Foundation

enum TunerHeaders {
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
