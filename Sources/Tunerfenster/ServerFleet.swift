import Combine
import Foundation

struct ServerProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var address: String
    var username: String
    var auth: String

    init(id: String = UUID().uuidString, name: String = "", connection: Connection) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        address = connection.address; username = connection.username; auth = connection.auth
    }

    var label: String {
        if !name.isEmpty { return name }
        return URLComponents(string: address)?.host ?? address
    }

    func connection() -> Connection {
        Connection(address: address, username: username,
                   password: Keychain.load(account: address + "|" + username), auth: auth)
    }
}

struct ServerProfileStore {
    static let key = "tvheadendServersV1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> [ServerProfile] {
        guard let data = defaults.data(forKey: Self.key),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return [] }
        return profiles
    }
    func save(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

@MainActor
final class ServerFleet: ObservableObject {
    struct Node: Identifiable {
        var profile: ServerProfile
        let monitor: Monitor
        var id: String { profile.id }
    }
    struct Tile: Identifiable {
        let server: Node
        let tuner: Tuner
        var id: String { server.id + "\n" + tuner.id }
    }

    @Published private(set) var nodes: [Node]
    @Published private(set) var activeID: String
    @Published private(set) var ready = false
    private var observers = [String: Set<AnyCancellable>]()
    private let store: ServerProfileStore
    private let persistSelection: (Connection) -> Void
    private var started = false
    private var globalPaused = false
    private var lastAudibleServerID: String?
    var active: Monitor { nodes.first { $0.id == activeID }?.monitor ?? nodes[0].monitor }
    var activeNode: Node { nodes.first { $0.id == activeID } ?? nodes[0] }
    var hasMultipleServers: Bool { nodes.count > 1 }
    var tiles: [Tile] { nodes.flatMap { node in node.monitor.tuners.map { Tile(server: node, tuner: $0) } } }

    init(store: ServerProfileStore = ServerProfileStore()) {
        self.store = store
        persistSelection = { $0.saveAsCurrent() }
        let monitor = Monitor()
        let profile = ServerProfile(id: "initial", connection: monitor.connection)
        nodes = [Node(profile: profile, monitor: monitor)]
        activeID = profile.id
        observe(nodes[0])
    }

    init(store: ServerProfileStore, nodes: [Node], activeID: String,
         persistSelection: @escaping (Connection) -> Void) {
        precondition(!nodes.isEmpty && nodes.contains { $0.id == activeID })
        self.store = store; self.nodes = nodes; self.activeID = activeID
        self.persistSelection = persistSelection
        ready = true
        for node in nodes { observe(node) }
    }

    func start() {
        guard !started else { return }
        started = true
        active.start { [weak self] initial in self?.loadProfiles(current: initial) }
    }

    private func loadProfiles(current: Connection) {
        var profiles = store.load()
        let existing = profiles.first { $0.address == current.address && $0.username == current.username }
        let selected = existing ?? ServerProfile(connection: current)
        if existing == nil { profiles.insert(selected, at: 0); store.save(profiles) }
        let primary = active
        nodes = profiles.map { profile in
            Node(profile: profile, monitor: profile.id == selected.id ? primary : Monitor())
        }
        activeID = selected.id
        observers.removeAll()
        for node in nodes {
            observe(node)
            guard node.id != selected.id else { continue }
            let profile = node.profile, monitor = node.monitor
            monitor.suspendPreviews(primary.viewingMode != .mosaic)
            Task { [weak self, weak monitor] in
                let connection = await Task.detached(priority: .userInitiated) { profile.connection() }.value
                guard let self, let monitor, self.nodes.contains(where: { $0.id == profile.id && $0.monitor === monitor }) else { return }
                monitor.start(initialConnection: connection, forceMosaic: true)
            }
        }
        ready = true
    }

    private func observe(_ node: Node) {
        var subscriptions = Set<AnyCancellable>()
        let serverID = node.id
        node.monitor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        node.monitor.$audioID.dropFirst().sink { [weak self, weak monitor = node.monitor] id in
            guard id != nil, let self, let monitor else { return }
            self.lastAudibleServerID = serverID
            DispatchQueue.main.async { [weak self, weak monitor] in
                guard let self, let monitor, monitor.audioID != nil else { return }
                for other in self.nodes where other.monitor !== monitor {
                    if let audio = other.monitor.audioID { other.monitor.toggleAudio(audio) }
                }
            }
        }.store(in: &subscriptions)
        observers[node.id] = subscriptions
    }

    func setMode(_ mode: ViewingMode) {
        active.setViewingMode(mode)
        for node in nodes where node.id != activeID { node.monitor.suspendPreviews(mode != .mosaic) }
    }

    func activate(_ id: String) {
        guard ready, id != activeID, let target = nodes.first(where: { $0.id == id }),
              target.monitor.connection.address == target.profile.address,
              target.monitor.connection.username == target.profile.username else { return }
        let old = active, mode = old.viewingMode
        if mode == .mosaic { old.focus(nil) } else { old.setViewingMode(.mosaic) }
        activeID = id
        target.monitor.suspendPreviews(false)
        if target.monitor.viewingMode != mode { target.monitor.setViewingMode(mode) }
        persistSelection(target.monitor.connection)
        for node in nodes where node.id != id { node.monitor.suspendPreviews(mode != .mosaic) }
    }

    func focus(_ tile: Tile) {
        activate(tile.server.id)
        guard activeID == tile.server.id else { return }
        active.focus(tile.tuner.id)
    }

    func togglePause() {
        globalPaused = !active.paused
        for node in nodes where node.monitor.paused != globalPaused { node.monitor.togglePause() }
    }

    func toggleMute() {
        if active.viewingMode == .recordings { active.toggleMute(); return }
        if let audible = nodes.first(where: { $0.monitor.audioID != nil }) {
            audible.monitor.toggleMute()
            return
        }
        let previous = nodes.first { $0.id == lastAudibleServerID }?.monitor ?? active
        previous.toggleMute()
        if nodes.allSatisfy({ $0.monitor.audioID == nil }) {
            nodes.first { node in
                node.monitor !== previous && node.monitor.playbackTuners.contains { node.monitor.preview(for: $0) != nil }
            }?.monitor.toggleMute()
        }
    }

    func followAll() { nodes.forEach { $0.monitor.followAll() } }
    func occupyAll() { nodes.forEach { $0.monitor.occupyAllTuners() } }
    func setPollingSeconds(_ seconds: Int) { nodes.forEach { $0.monitor.setPollingSeconds(seconds) } }
    func refreshAll() {
        for node in nodes { Task { await node.monitor.refresh(reloadCatalog: true) } }
    }

    func save(id: String?, name: String, connection: Connection) throws {
        guard ready else { throw AppError.message("serversLoading") }
        guard connection.baseURL != nil, ["digest", "basic", "none"].contains(connection.auth) else {
            throw AppError.message("invalidAddressInput")
        }
        let scope = SelectionStore.scope(for: connection)
        guard !nodes.contains(where: { node in
            let saved = Connection(address: node.profile.address, username: node.profile.username, password: "", auth: node.profile.auth)
            return node.id != id && SelectionStore.scope(for: saved) == scope
        }) else {
            throw AppError.message("duplicateServer")
        }
        if UserDefaults.standard.string(forKey: "serverAddress") == nil, active.connection.baseURL != nil {
            try active.connection.save()
        }
        if let id, let index = nodes.firstIndex(where: { $0.id == id }) {
            let node = nodes[index]
            if connection != node.monitor.connection { try node.monitor.apply(connection, asCurrent: id == activeID) }
            nodes[index].profile = ServerProfile(id: id, name: name, connection: connection)
        } else {
            try Keychain.save(password: connection.password, account: connection.address + "|" + connection.username)
            let node = Node(profile: ServerProfile(name: name, connection: connection), monitor: Monitor())
            nodes.append(node); observe(node)
            node.monitor.suspendPreviews(active.viewingMode != .mosaic)
            if globalPaused { node.monitor.togglePause() }
            node.monitor.start(initialConnection: connection, forceMosaic: true)
        }
        store.save(nodes.map(\.profile))
    }

    func remove(_ id: String) {
        guard ready, nodes.count > 1, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        if id == activeID, let next = nodes.first(where: { $0.id != id }) { activate(next.id) }
        guard activeID != id else { return }
        let node = nodes.remove(at: index)
        observers[id] = nil
        node.monitor.shutdown()
        store.save(nodes.map(\.profile))
    }

    func shutdown() { nodes.forEach { $0.monitor.shutdown() }; started = false; ready = false }
}
