import SwiftUI
import AppKit

struct RecordingListPreferences {
    static let foldersKey = "recordingExpandedFoldersV1"
    var defaults: UserDefaults = .standard

    var expandedFolders: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.foldersKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.foldersKey) }
    }
}
