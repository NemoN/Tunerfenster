import Foundation

/// Text and ordering belong to a catalogue revision, not to each scroll/layout pass.
final class RecordingListSnapshot {
    let tree: RecordingFolderTree
    let columns: RecordingMetadataColumns
    let rows: [String: RecordingListRow]
    let rootEntries: [RecordingListEntry]
    let folderEntries: [String: [RecordingListEntry]]
    let filtered: [SavedRecording]
    let term: String

    init(items: [SavedRecording], storageRoots: [RecordingStorage], sort: RecordingSort, term: String) {
        self.term = term
        let tree = RecordingFolderTree(items: items, storageRoots: storageRoots).flatteningSingleRecordingFolders()
        self.tree = tree
        var folderNames = [String: String]()
        func collect(_ folders: [RecordingFolder]) {
            for folder in folders { folderNames[folder.id] = folder.name; collect(folder.folders) }
        }
        collect(tree.folders)
        let rows = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, RecordingListRow(item: item, folder: tree.paths[item.id],
                                      ancestors: (tree.ancestors[item.id] ?? []).compactMap { folderNames[$0] }))
        })
        self.rows = rows
        columns = RecordingMetadataColumns(rows: Array(rows.values))
        let names = rows.mapValues(\.fullName)
        rootEntries = sort.sorted(folders: tree.folders, recordings: tree.unfiled, names: names)
        var children = [String: [RecordingListEntry]]()
        func prepare(_ folders: [RecordingFolder], within ancestors: [String]) {
            for folder in folders {
                let path = ancestors + [folder.name]
                children[folder.id] = sort.sorted(folders: folder.folders, recordings: folder.recordings, within: path, names: names)
                prepare(folder.folders, within: path)
            }
        }
        prepare(tree.folders, within: [])
        folderEntries = children
        filtered = term.isEmpty ? items : sort.sorted(items.filter { rows[$0.id]?.matches(term) == true }, names: names)
    }
}

struct RecordingListRow {
    let item: SavedRecording
    let fullName: String
    let folderTitle: String
    let fullDate: String?
    let date: String?
    let duration: String?
    let description: String
    let statusLabel: String
    let playLabel: String
    let deleteHelp: String
    let deleteLabel: String
    let deletingLabel: String
    private let searchable: [String]

    init(item: SavedRecording, folder: String?, ancestors: [String]) {
        self.item = item
        let name = item.name, date = item.compactDateLabel, fullDate = item.dateLabel, duration = item.compactDurationLabel
        fullName = name
        folderTitle = RecordingTitle.withoutFolderPrefix(name, folders: ancestors)
        self.date = date; self.fullDate = fullDate; self.duration = duration
        statusLabel = item.statusLabel
        let durationDescription = duration.map { L10n.text("recordingDurationValue", $0) } ?? L10n.text("recordingDurationUnavailable")
        description = [item.statusLabel, name, item.channelname, fullDate, durationDescription, folder]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        playLabel = L10n.text("playRecording", name)
        deleteHelp = L10n.text(item.isRunning ? "recordingDeleteRunning" : "deleteRecordingNamed", name)
        deleteLabel = L10n.text("deleteRecordingNamed", name)
        deletingLabel = L10n.text("deletingRecording", name)
        searchable = [name, item.channelname, item.subtitleText, item.detail, folder].compactMap { $0 }
    }

    func matches(_ term: String) -> Bool { searchable.contains { $0.localizedStandardContains(term) } }
}

/// UI-only state (selection, mute, expansion and pane width) does not invalidate it.
final class RecordingListCache {
    private struct Key: Equatable {
        let sort: RecordingSort
        let term: String
        let language: AppLanguage
        let timeZone: String
    }
    private var cached: (key: Key, value: RecordingListSnapshot)?

    func invalidate() { cached = nil }

    func snapshot(items: [SavedRecording], storageRoots: [RecordingStorage], sort: RecordingSort, search: String) -> RecordingListSnapshot {
        let key = Key(sort: sort, term: search.trimmingCharacters(in: .whitespacesAndNewlines),
                      language: L10n.language, timeZone: TimeZone.current.identifier)
        if let cached, cached.key == key { return cached.value }
        let result = RecordingListSnapshot(items: items, storageRoots: storageRoots, sort: sort, term: key.term)
        cached = (key, result)
        return result
    }
}
