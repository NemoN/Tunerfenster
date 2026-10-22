import Foundation

/// Stores channel assignments and viewing preferences separately for each server/account.
struct SelectionStore {
    static let key = "manualSelectionsV1"
    static let viewingKey = "viewingStateV1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func scope(for connection: Connection) -> String? {
        guard let url = connection.baseURL,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "http" && parts.port == 80) || (parts.scheme == "https" && parts.port == 443) { parts.port = nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let address = parts.string else { return nil }
        return address + "\n" + connection.username
    }

    private var document: [String: [String: String]] {
        guard let data = defaults.data(forKey: Self.key),
              let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return values
    }

    func load(scope: String) -> [String: String] { document[scope] ?? [:] }

    func save(_ selections: [String: String], scope: String) {
        var values = document
        values[scope] = selections
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private var viewingDocument: [String: ViewingState] {
        guard let data = defaults.data(forKey: Self.viewingKey),
              let values = try? JSONDecoder().decode([String: ViewingState].self, from: data) else { return [:] }
        return values
    }

    func loadViewingState(scope: String) -> ViewingState { viewingDocument[scope] ?? ViewingState() }

    func saveViewingState(_ state: ViewingState, scope: String) {
        var values = viewingDocument
        values[scope] = state
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.viewingKey)
    }
}
