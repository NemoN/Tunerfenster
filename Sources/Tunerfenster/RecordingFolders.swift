import Foundation

struct RecordingFile: Decodable, Sendable {
    var filename: String? = nil
}

struct RecordingStorage: Decodable, Sendable {
    let uuid: String
    var name: String? = nil
    var storage: String? = nil
}

struct RecordingFolder: Identifiable {
    let id: String
    let name: String
    var folders: [RecordingFolder] = []
    var recordings: [SavedRecording] = []
    var count: Int { recordings.count + folders.reduce(0) { $0 + $1.count } }
}

struct RecordingFolderTree {
    private(set) var folders = [RecordingFolder]()
    private(set) var unfiled = [SavedRecording]()
    private(set) var paths = [String: String]()
    private(set) var ancestors = [String: [String]]()

    func sorted(using order: RecordingSort) -> Self {
        var result = self
        result.folders = order.sorted(folders: folders)
        result.unfiled = order.sorted(unfiled)
        return result
    }

    func flatteningSingleRecordingFolders() -> Self {
        var result = self
        var visibleFolders = Set<String>()
        func flatten(_ folders: [RecordingFolder], into recordings: inout [SavedRecording]) -> [RecordingFolder] {
            folders.compactMap { original in
                var folder = original
                folder.folders = flatten(original.folders, into: &folder.recordings)
                if folder.count == 1 {
                    recordings.append(contentsOf: folder.recordings)
                    return nil
                }
                visibleFolders.insert(folder.id)
                return folder
            }
        }
        result.folders = flatten(folders, into: &result.unfiled)
        result.ancestors = ancestors.mapValues { $0.filter { visibleFolders.contains($0) } }
        return result
    }

    init(items: [SavedRecording], storageRoots: [RecordingStorage]) {
        let storages = storageRoots.compactMap { profile -> Storage? in
            guard let path = ServerPath(profile.storage), path.absolute else { return nil }
            return Storage(id: profile.uuid, name: profile.name, path: path.parts)
        }.sorted { $0.path.count > $1.path.count }
        let parents = items.map { item -> ServerPath? in
            // The actual filename wins over the directory originally requested
            // by a timer, including after a file was moved on the server.
            let file = item.filename.flatMap { $0.isEmpty ? nil : $0 } ?? item.files?.compactMap(\.filename).first { !$0.isEmpty }
            if let file, var path = ServerPath(file), !path.parts.isEmpty {
                path.parts.removeLast()
                return path
            }
            return ServerPath(item.directory)
        }
        var inferred = [String: [String]]()
        var singleParent = [String: Bool]()
        for (item, parent) in zip(items, parents) {
            guard let parent, parent.absolute, Self.storage(for: item, parent: parent, storages: storages) == nil else { continue }
            let key = item.config_name ?? ""
            if let previous = inferred[key] {
                singleParent[key] = singleParent[key] == true && previous == parent.parts
                inferred[key] = Self.commonPrefix(previous, parent.parts)
            } else { inferred[key] = parent.parts; singleParent[key] = true }
        }
        // Without profile access, retain the folder name if all files share
        // one parent. Otherwise that sole folder would disappear from the UI.
        for (key, prefix) in inferred {
            if !prefix.isEmpty, singleParent[key] == true { inferred[key] = Array(prefix.dropLast()) }
        }

        let locations = zip(items, parents).map { item, parent -> Location? in
            guard let parent else { return nil }
            let storage = Self.storage(for: item, parent: parent, storages: storages)
            let base = parent.absolute ? storage?.path ?? inferred[item.config_name ?? ""] ?? [] : []
            let parts = Array(parent.parts.dropFirst(base.count))
            let rootParts = storage?.path ?? base
            let root = parent.absolute || storage != nil ? "/" + rootParts.joined(separator: "/") : "relative:\(item.config_name ?? "")"
            let label = storage?.name.flatMap { $0.isEmpty ? nil : $0 } ?? rootParts.last ?? L10n.text("recordingOtherFolders")
            return Location(root: root, label: label, parts: parts)
        }
        let roots = Set(locations.compactMap { $0?.root })
        let duplicateLabels = Dictionary(grouping: locations.compactMap { $0 }, by: \.label)
            .mapValues { Set($0.map(\.root)).count > 1 }
        var nodes = [String: FolderBuilder]()
        for (item, location) in zip(items, locations) {
            guard let location else { unfiled.append(item); continue }
            var names = location.parts
            if roots.count > 1 {
                names.insert(duplicateLabels[location.label] == true ? location.root : location.label, at: 0)
            }
            paths[item.id] = names.joined(separator: " / ")
            // Files directly in a storage root need no synthetic profile folder.
            guard !location.parts.isEmpty else { unfiled.append(item); continue }
            var parent: FolderBuilder?
            var ancestorIDs = [String]()
            for depth in names.indices {
                // Length-prefix components so punctuation in folder names
                // cannot cause two different paths to share an identifier.
                let id = ([location.root] + Array(names.prefix(depth + 1))).map { "\($0.utf8.count):\($0)" }.joined()
                ancestorIDs.append(id)
                let node: FolderBuilder
                if let existing = nodes[id] { node = existing }
                else {
                    node = FolderBuilder(id: id, name: names[depth])
                    nodes[id] = node
                    if let parent { parent.children.append(node) }
                }
                parent = node
            }
            ancestors[item.id] = ancestorIDs
            parent?.recordings.append(item)
        }
        let children = Set(nodes.values.flatMap { $0.children.map(\.id) })
        folders = nodes.values.filter { !children.contains($0.id) }.map { $0.folder }.sorted(by: Self.ordered)
    }

    private static func ordered(_ lhs: RecordingFolder, _ rhs: RecordingFolder) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    private static func commonPrefix(_ lhs: [String], _ rhs: [String]) -> [String] {
        Array(zip(lhs, rhs).prefix { $0 == $1 }.map(\.0))
    }

    private static func storage(for item: SavedRecording, parent: ServerPath, storages: [Storage]) -> Storage? {
        guard parent.absolute else {
            return storages.first { $0.id == item.config_name } ?? (item.config_name == nil && storages.count == 1 ? storages.first : nil)
        }
        let matches = storages.filter { parent.parts.starts(with: $0.path) }
        return matches.first { $0.id == item.config_name } ?? matches.first
    }

    private struct Storage { let id: String; let name: String?; let path: [String] }
    private struct Location { let root: String; let label: String; let parts: [String] }

    private final class FolderBuilder {
        let id: String
        let name: String
        var children = [FolderBuilder]()
        var recordings = [SavedRecording]()
        init(id: String, name: String) { self.id = id; self.name = name }
        var folder: RecordingFolder {
            RecordingFolder(id: id, name: name, folders: children.map(\.folder).sorted(by: RecordingFolderTree.ordered), recordings: recordings)
        }
    }

    private struct ServerPath {
        let absolute: Bool
        var parts: [String]
        init?(_ raw: String?) {
            guard let raw, !raw.isEmpty else { return nil }
            absolute = raw.hasPrefix("/")
            var result = [String]()
            for component in raw.split(separator: "/").map(String.init) {
                if component == "." { continue }
                if component == ".." {
                    guard !result.isEmpty else { return nil }
                    result.removeLast()
                } else { result.append(component) }
            }
            parts = result
        }
    }
}
