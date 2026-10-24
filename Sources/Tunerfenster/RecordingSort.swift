import Foundation

enum RecordingListEntry: Identifiable {
    case folder(RecordingFolder)
    case recording(SavedRecording)

    var id: String {
        switch self {
        case .folder(let folder): "folder/\(folder.id)"
        case .recording(let recording): "recording/\(recording.id)"
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): folder.name
        case .recording(let recording): recording.name
        }
    }
}

enum RecordingSort: String, CaseIterable {
    case nameAscending, nameDescending, dateNewest, dateOldest, durationLongest, durationShortest

    enum Field: String { case name, date, duration }
    static let preferenceKey = "recordingSort"
    var field: Field {
        switch self {
        case .nameAscending, .nameDescending: .name
        case .dateNewest, .dateOldest: .date
        case .durationLongest, .durationShortest: .duration
        }
    }
    var ascending: Bool { self == .nameAscending || self == .dateOldest || self == .durationShortest }
    var labelKey: String { "recordingSort" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    func selecting(_ field: Field) -> Self {
        switch field {
        case .name: self == .nameAscending ? .nameDescending : .nameAscending
        case .date: self == .dateNewest ? .dateOldest : .dateNewest
        case .duration: self == .durationLongest ? .durationShortest : .durationLongest
        }
    }

    func sorted(_ items: [SavedRecording], names: [String: String] = [:], locale: Locale = L10n.language.locale) -> [SavedRecording] {
        // Episode metadata is parsed once per item, rather than in every comparison.
        items.map { (item: $0, name: names[$0.id] ?? $0.name) }.sorted {
            precedes(name: $0.name, date: Self.timestamp($0.item.start), duration: Self.length($0.item), id: $0.item.id,
                     otherName: $1.name, otherDate: Self.timestamp($1.item.start), otherDuration: Self.length($1.item), otherID: $1.item.id, locale: locale)
        }.map(\.item)
    }

    func sorted(folders: [RecordingFolder], locale: Locale = L10n.language.locale) -> [RecordingFolder] {
        orderedFolders(folders, locale: locale).map(\.folder)
    }

    func sorted(folders: [RecordingFolder], recordings: [SavedRecording], within folderNames: [String] = [], names: [String: String] = [:], locale: Locale = L10n.language.locale) -> [RecordingListEntry] {
        let entries = folders.map { (entry: RecordingListEntry.folder($0), name: $0.name, date: Self.newestTimestamp(in: $0), duration: Self.longestDuration(in: $0)) } +
            recordings.map { (entry: RecordingListEntry.recording($0), name: RecordingTitle.withoutFolderPrefix(names[$0.id] ?? $0.name, folders: folderNames), date: Self.timestamp($0.start), duration: Self.length($0)) }
        return entries.sorted {
            precedes(name: $0.name, date: $0.date, duration: $0.duration, id: $0.entry.id,
                     otherName: $1.name, otherDate: $1.date, otherDuration: $1.duration, otherID: $1.entry.id, locale: locale)
        }.map(\.entry)
    }

    private static func newestTimestamp(in folder: RecordingFolder) -> Double? {
        (folder.recordings.compactMap { timestamp($0.start) } + folder.folders.compactMap { newestTimestamp(in: $0) }).max()
    }

    private static func length(_ recording: SavedRecording) -> Double? {
        let value = recording.recordedDuration
        return value >= 1 && value < Double(Int.max) ? value : nil
    }

    private static func longestDuration(in folder: RecordingFolder) -> Double? {
        (folder.recordings.compactMap(length) + folder.folders.compactMap { longestDuration(in: $0) }).max()
    }

    private struct FolderEntry { let folder: RecordingFolder; let newest: Double?; let duration: Double? }

    private func orderedFolders(_ folders: [RecordingFolder], locale: Locale) -> [FolderEntry] {
        folders.map { original in
            let children = orderedFolders(original.folders, locale: locale)
            var folder = original
            folder.folders = children.map(\.folder)
            folder.recordings = sorted(original.recordings, locale: locale)
            // A folder's date is the newest recording anywhere inside it.
            let newest = (original.recordings.compactMap { Self.timestamp($0.start) } + children.compactMap(\.newest)).max()
            let duration = (original.recordings.compactMap(Self.length) + children.compactMap(\.duration)).max()
            return FolderEntry(folder: folder, newest: newest, duration: duration)
        }.sorted {
            precedes(name: $0.folder.name, date: $0.newest, duration: $0.duration, id: $0.folder.id,
                     otherName: $1.folder.name, otherDate: $1.newest, otherDuration: $1.duration, otherID: $1.folder.id, locale: locale)
        }
    }

    private func precedes(name: String, date: Double?, duration: Double?, id: String,
                          otherName: String, otherDate: Double?, otherDuration: Double?, otherID: String, locale: Locale) -> Bool {
        let names = name.compare(otherName, options: [.numeric, .caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
        if field == .duration {
            if duration != otherDuration {
                guard let duration else { return false }
                guard let otherDuration else { return true }
                return ascending ? duration < otherDuration : duration > otherDuration
            }
            if names != .orderedSame { return names == .orderedAscending }
        }
        if field == .name, names != .orderedSame {
            return names == (ascending ? .orderedAscending : .orderedDescending)
        }
        // Unknown dates stay at the end in either direction. Equal names
        // use newest-first dates; equal dates use A–Z, then a stable UUID.
        if date != otherDate {
            guard let date else { return false }
            guard let otherDate else { return true }
            return self == .dateOldest ? date < otherDate : date > otherDate
        }
        if names != .orderedSame { return names == .orderedAscending }
        return id < otherID
    }

    private static func timestamp(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? $0 : nil }
    }
}
