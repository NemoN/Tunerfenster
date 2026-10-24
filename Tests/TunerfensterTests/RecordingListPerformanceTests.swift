import XCTest
@testable import Tunerfenster

final class RecordingListPerformanceTests: XCTestCase {
    @MainActor func testRepeatedListPreparation() throws {
        guard ProcessInfo.processInfo.environment["TUNERFENSTER_LIST_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in list preparation benchmark")
        }
        let items = (0..<100).map { index in
            SavedRecording(uuid: String(format: "%032x", index), disp_title: index % 2 == 0 ? "Tatort" : "Reportage",
                           disp_description: "Eine ausführliche Beschreibung der Sendung.\nSerie: Tatort\nFolge: Fall \(index)\nGenre: Krimi",
                           channelname: "Das Erste HD", start: 1_740_947_400 + Double(index * 1000), duration: 5400,
                           filesize: 100, sched_status: "completed", filename: "/recordings/Krimis/Folge-\(index).ts")
        }
        let roots = [RecordingStorage(uuid: "default", storage: "/recordings")]
        var checksum = 0
        let clock = ContinuousClock(), start = clock.now
        for _ in 0..<30 {
            let tree = RecordingFolderTree(items: items, storageRoots: roots).flatteningSingleRecordingFolders()
            let filtered = RecordingSort.dateNewest.sorted(items.filter { $0.matches("") })
            let columns = RecordingMetadataColumns(items: items)
            checksum += filtered.count + Int(columns.duration)
            func visit(_ folders: [RecordingFolder], _ recordings: [SavedRecording], _ names: [String]) {
                for entry in RecordingSort.dateNewest.sorted(folders: folders, recordings: recordings, within: names) {
                    switch entry {
                    case .folder(let folder): visit(folder.folders, folder.recordings, names + [folder.name])
                    case .recording(let item):
                        let title = RecordingTitle.withoutFolderPrefix(item.name, folders: names)
                        checksum += title.count + item.name.count + (item.dateLabel?.count ?? 0) + (item.compactDateLabel?.count ?? 0)
                    }
                }
            }
            visit(tree.folders, tree.unfiled, [])
        }
        let elapsed = start.duration(to: clock.now)
        print("LIST_PREPARATION_UNCACHED: \(elapsed), 30 passes, checksum \(checksum)")
        XCTAssertGreaterThan(checksum, 0)

        let cache = RecordingListCache()
        let coldStart = clock.now
        _ = cache.snapshot(items: items, storageRoots: roots, sort: .dateNewest, search: "")
        let cold = coldStart.duration(to: clock.now)
        let warmStart = clock.now
        var warmChecksum = 0
        for _ in 0..<30 {
            let snapshot = cache.snapshot(items: items, storageRoots: roots, sort: .dateNewest, search: "")
            warmChecksum += snapshot.filtered.count + Int(snapshot.columns.duration)
            for row in snapshot.rows.values {
                warmChecksum += row.folderTitle.count + row.fullName.count + (row.fullDate?.count ?? 0) + (row.date?.count ?? 0)
            }
        }
        print("LIST_PREPARATION_CACHED: \(warmStart.duration(to: clock.now)), 30 passes; first build \(cold); checksum \(warmChecksum)")
        XCTAssertEqual(warmChecksum, checksum)
    }
}
