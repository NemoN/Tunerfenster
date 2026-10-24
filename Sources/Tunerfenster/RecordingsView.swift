import SwiftUI

struct RecordingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var library: RecordingLibrary
    @AppStorage(RecordingSort.preferenceKey) private var sort = RecordingSort.dateNewest
    @State private var search = ""
    @State private var expandedFolders = RecordingListPreferences().expandedFolders

    var body: some View {
        let snapshot = library.listSnapshot(sort: sort, search: search)
        let term = snapshot.term
        let filtered = snapshot.filtered
        let selectedFolders = snapshot.tree.ancestors[library.selected?.id ?? ""] ?? []
        let columns = snapshot.columns
        RecordingSplitView(name: "TunerfensterRecordingsV1", isVertical: true, minimumFirst: 280, minimumSecond: 320) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("recordingsMode")).font(.headline)
                    Spacer()
                    if library.loading { ProgressView().controlSize(.small) }
                    sortButton(.name, symbol: "textformat.abc", label: "sortRecordingsByName")
                    sortButton(.date, symbol: "calendar", label: "sortRecordingsByDate")
                    sortButton(.duration, symbol: "clock", label: "sortRecordingsByDuration")
                    Text(String(library.items.count)).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.horizontal, 12).padding(.top, 12)
                TextField(L10n.text("searchRecordings"), text: $search)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                if let error = library.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(ThemeColors.warning).font(.callout)
                        Button(L10n.text("retryRecordings")) { Task { await library.refresh() } }.disabled(library.loading)
                    }.padding(.horizontal, 12)
                }
                if let error = library.deletionError {
                    HStack(alignment: .top, spacing: 8) {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(ThemeColors.warning).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { library.dismissDeletionError() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel(L10n.text("dismissRecordingDeleteError"))
                    }.padding(.horizontal, 12)
                }
                if let error = library.progressError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(ThemeColors.warning).font(.callout)
                        Button(L10n.text("retryRecordings")) { Task { await library.retryProgressSync() } }
                    }.padding(.horizontal, 12)
                }
                if (!library.configured || library.loading) && library.items.isEmpty {
                    empty("loadingRecordings", symbol: "rectangle.stack")
                } else if filtered.isEmpty {
                    empty(search.isEmpty ? "noRecordings" : "noMatchingRecordings", symbol: "rectangle.stack")
                } else {
                    GeometryReader { geometry in
                        let visibility = columns.visibility(inListWidth: geometry.size.width)
                        List(selection: Binding<String?>(get: { library.selected?.id }, set: { id in
                            guard let item = library.items.first(where: { $0.id == id }) else { return }
                            library.select(item)
                        })) {
                            if !term.isEmpty {
                                ForEach(filtered) { item in
                                    recordingRow(snapshot.rows[item.id]!, columns: columns, visibility: visibility, inFolder: false)
                                }
                            } else {
                                ForEach(snapshot.rootEntries) { entry in
                                    switch entry {
                                    case .folder(let folder):
                                        RecordingFolderGroup(folder: folder, snapshot: snapshot, expanded: $expandedFolders) { item in
                                            recordingRow(snapshot.rows[item.id]!, columns: columns, visibility: visibility, inFolder: true)
                                        }
                                    case .recording(let item):
                                        recordingRow(snapshot.rows[item.id]!, columns: columns, visibility: visibility, inFolder: false)
                                    }
                                }
                            }
                        }.listStyle(.inset).scrollContentBackground(.hidden).accessibilityLabel(L10n.text("recordingsMode"))
                            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                                guard ids.count == 1, let id = ids.first,
                                      let item = library.items.first(where: { $0.id == id }), item.canPlay else { return }
                                Task { await library.play(item) }
                            }
                            .onDeleteCommand {
                                if let selected = library.selected { library.requestDeletion(selected) }
                            }
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 620, maxWidth: .infinity)
            .recordingPanel()
        } second: {
            RecordingPlayerView(library: library, playback: library.playback)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedFolders, initial: true) { _, ids in expandedFolders.formUnion(ids) }
        .onChange(of: term) { _, value in if value.isEmpty { expandedFolders.formUnion(selectedFolders) } }
        .onChange(of: expandedFolders) { _, folders in RecordingListPreferences().expandedFolders = folders }
        .alert(L10n.text("deleteRecordingTitle"), isPresented: Binding(
            get: { library.deletionCandidate != nil },
            set: { if !$0 { library.cancelDeletion() } }
        ), presenting: library.deletionCandidate) { item in
            Button(L10n.text("deleteRecordingConfirm"), role: .destructive) { library.confirmDeletion() }
                .disabled(!library.canDelete(item))
            Button(L10n.text("cancel"), role: .cancel) { library.cancelDeletion() }
        } message: { item in
            Text(L10n.text("deleteRecordingMessage", item.name))
        }
    }

    private func sortButton(_ field: RecordingSort.Field, symbol: String, label: String) -> some View {
        Button { sort = sort.selecting(field) } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                    .font(.caption2).opacity(sort.field == field ? 1 : 0)
            }.frame(width: 32, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(sort.field == field ? Color.accentColor : .secondary)
        .help(L10n.text(sort.selecting(field).labelKey) + (field == .duration ? "\n" + L10n.text("recordingSortDurationFolders") : ""))
        .accessibilityLabel(L10n.text(label))
        .accessibilityValue(L10n.text(sort.field == field ? sort.labelKey : "recordingSortInactive"))
        .accessibilityIdentifier("sortRecordings/\(field.rawValue)")
    }

    private func recordingRow(_ row: RecordingListRow, columns: RecordingMetadataColumns, visibility: RecordingMetadataColumns.Visibility, inFolder: Bool) -> some View {
        let item = row.item
        let duration = row.duration
        let progress = library.progress(for: item)
        let progressLabel = progress.label
        return HStack(spacing: 6) {
            Image(systemName: progress.symbol).foregroundStyle(.secondary)
                .frame(width: 14).help(progressLabel).accessibilityLabel(progressLabel)
            HStack(spacing: 5) {
                Text(inFolder ? row.folderTitle : row.fullName).font(.system(size: 13, weight: .medium))
                if item.isRunning {
                    Image(systemName: "circle.fill").font(.system(size: 8))
                        .foregroundStyle(ThemeColors.recording).layoutPriority(1)
                        .help(row.statusLabel).accessibilityHidden(true)
                }
                if item.hasError || !item.canPlay {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(ThemeColors.warning)
                        .layoutPriority(1).help(row.statusLabel).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if visibility == .all {
                Text(item.channelname ?? "").foregroundStyle(.secondary)
                    .frame(width: columns.channel, alignment: .center)
                Text(row.date ?? "").foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: columns.date, alignment: .leading)
            }
            if visibility != .titleOnly {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.caption2).frame(width: 12).accessibilityHidden(true)
                    Text(duration ?? "—").monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .frame(width: columns.duration, alignment: .trailing)
                .help(L10n.text(duration == nil ? "recordingDurationUnavailable" : "scheduledRecordingDuration"))
            }
            recordingDeleteButton(row)
        }
        .font(.caption).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(row.description + " · " + progressLabel)
        .frame(height: 24)
        .tag(item.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.description + " · " + progressLabel)
        .accessibilityAction(named: Text(row.playLabel)) { Task { await library.play(item) } }
        .accessibilityAction(named: Text(L10n.text("deleteRecording"))) { library.requestDeletion(item) }
        .contextMenu {
            Button { library.markSeen(true, for: item) } label: {
                Label(L10n.text("recordingMarkSeen"), systemImage: "eye.fill")
            }.disabled(progress.seen || !library.canMarkSeen(item))
            Button { library.markSeen(false, for: item) } label: {
                Label(L10n.text("recordingMarkUnseen"), systemImage: "circle")
            }.disabled(!progress.seen && progress.position == 0 || !library.canMarkSeen(item))
            Divider()
            Button { Task { await library.play(item) } } label: {
                Label(L10n.text("recordingStartPlayback"), systemImage: "play.fill")
            }.disabled(!item.canPlay)
            Button { Task { await library.play(item, fromBeginning: true) } } label: {
                Label(L10n.text("recordingPlayFromBeginning"), systemImage: "backward.end.fill")
            }.disabled(!item.canPlay)
            Button(role: .destructive) { library.requestDeletion(item) } label: {
                Label(L10n.text("deleteRecording"), systemImage: "trash")
            }.disabled(!library.canDelete(item))
        }
    }

    private func recordingDeleteButton(_ row: RecordingListRow) -> some View {
        let item = row.item
        return Button { library.requestDeletion(item) } label: {
            if library.deletingID == item.id {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
        }
        .buttonStyle(.borderless)
        .disabled(!library.canDelete(item))
        .help(row.deleteHelp)
        .accessibilityLabel(library.deletingID == item.id ? row.deletingLabel : row.deleteLabel)
        .accessibilityIdentifier("deleteRecording/\(item.id)")
        .fixedSize()
    }

    private func empty(_ key: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2)
            Text(L10n.text(key)).multilineTextAlignment(.center).font(.callout)
        }.foregroundStyle(.secondary).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecordingMetadataColumns {
    enum Visibility { case all, durationOnly, titleOnly }
    let channel: CGFloat
    let date: CGFloat
    let duration: CGFloat

    func visibility(inListWidth width: CGFloat) -> Visibility {
        // One decision for the whole list, independent of each row's indentation.
        let listInsets: CGFloat = 32
        let minimumTitleWidth: CGFloat = 160
        let base = listInsets + minimumTitleWidth
        if width >= base + channel + date + duration + 70 { return .all }
        if width >= base + duration + 58 { return .durationOnly }
        return .titleOnly
    }

    init(items: [SavedRecording]) {
        self.init(channels: items.compactMap(\.channelname), dates: items.compactMap(\.compactDateLabel), durations: items.compactMap(\.compactDurationLabel))
    }

    init(rows: [RecordingListRow]) {
        self.init(channels: rows.compactMap { $0.item.channelname }, dates: rows.compactMap(\.date), durations: rows.compactMap(\.duration))
    }

    private init(channels: [String], dates: [String], durations: [String]) {
        let font = NSFont.preferredFont(forTextStyle: .caption1, options: [:])
        let dateFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        channel = min(100, ceil(channels.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0))
        date = min(120, ceil(dates.map {
            ($0 as NSString).size(withAttributes: [.font: dateFont]).width
        }.max() ?? 0))
        duration = min(90, 15 + ceil((durations + ["0:00:00"])
            .map { ($0 as NSString).size(withAttributes: [.font: dateFont]).width }.max() ?? 0))
    }
}

private struct RecordingFolderGroup<Row: View>: View {
    let folder: RecordingFolder
    let snapshot: RecordingListSnapshot
    @Binding var expanded: Set<String>
    @ViewBuilder let row: (SavedRecording) -> Row

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(folder.id) },
            set: { if $0 { expanded.insert(folder.id) } else { expanded.remove(folder.id) } }
        )) {
            ForEach(snapshot.folderEntries[folder.id] ?? []) { entry in
                switch entry {
                case .folder(let child): RecordingFolderGroup(folder: child, snapshot: snapshot, expanded: $expanded, row: row)
                case .recording(let item): row(item)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Label(folder.name, systemImage: expanded.contains(folder.id) ? "folder.fill" : "folder")
                    .font(.callout.weight(.medium)).lineLimit(1).help(folder.name)
                Spacer(minLength: 4)
                Text(String(folder.count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(folder.name)
            .accessibilityValue(L10n.text("recordingFolderCount", String(folder.count)))
        }
        .accessibilityIdentifier("recordingFolder/\(folder.id)")
    }
}

private struct RecordingPlayerView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var playback: Playback
    private var needsStart: Bool { !library.playbackRequested }
    private var needsReplay: Bool { playback.ended || playback.failed || library.playbackError != nil }
    private var playerMessage: String {
        if let error = library.playbackError { return error.localizedDescription }
        if playback.ended { return L10n.text("recordingPlaybackEnded") }
        if playback.failed { return L10n.text("recordingPlaybackInterrupted") }
        return playback.status
    }

    var body: some View {
        Group {
            if let item = library.selected {
                if item.subtitleText != nil || item.detail != nil {
                    RecordingSplitView(name: "TunerfensterRecordingDetailsV1", isVertical: false, minimumFirst: 220, minimumSecond: 70, initialFraction: 0.72) {
                        playbackPanel(item)
                            .frame(minHeight: 220, idealHeight: 540, maxHeight: .infinity)
                    } second: {
                        programmeDetails(item)
                            .frame(minHeight: 70, idealHeight: 150, maxHeight: .infinity)
                            .recordingPanel()
                    }
                } else {
                    playbackPanel(item)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle").font(.system(size: 36, weight: .light))
                    Text(L10n.text("selectRecording")).font(.headline)
                    Text(library.playbackError?.localizedDescription ?? L10n.text("selectRecordingHelp"))
                        .font(.callout).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .recordingPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playbackPanel(_ item: SavedRecording) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline).lineLimit(2).textSelection(.enabled)
                Text([item.channelname, item.dateLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(ThemeColors.detailSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background { DetailPanelBackground(cornerRadius: 0) }
            player(item)
                .padding(.horizontal, 1)
        }
        .recordingPanel()
    }

    private func player(_ item: SavedRecording) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black
                if !item.canPlay {
                    Text(item.statusLabel).foregroundStyle(.white).padding(20)
                } else if needsStart {
                    Button { Task { await library.play(item) } } label: {
                        Label(L10n.text("recordingStartPlayback"), systemImage: "play.fill")
                    }.controlSize(.large).accessibilityIdentifier("startSelectedRecording")
                } else {
                    VideoSurface(playback: playback, cornerRadius: 8)
                        .opacity(playback.hasVideo ? 1 : 0)
                    if library.opening || !playback.hasVideo || needsReplay {
                        VStack(spacing: 8) {
                            if library.opening { ProgressView().controlSize(.small) }
                            Text(playerMessage).font(.callout).multilineTextAlignment(.center)
                        }.padding(20).foregroundStyle(.white)
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            RecordingTransportView(library: library, playback: playback, item: item)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background { DetailPanelBackground(cornerRadius: 0) }
                .overlay(alignment: .top) { Divider().opacity(0.6) }
            if !needsStart && playback.resumeFailed {
                Label(L10n.text("recordingResumeFailed"), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(ThemeColors.warning).padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private func programmeDetails(_ item: SavedRecording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("recordingProgrammeDetails"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(ThemeColors.detailSecondary)
                if let subtitle = item.subtitleText { Text(subtitle).font(.headline).textSelection(.enabled) }
                if let detail = item.detail { Text(detail).font(.callout).lineSpacing(3).textSelection(.enabled) }
            }.frame(maxWidth: 760, alignment: .leading).padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(L10n.text("recordingProgrammeDetails"))
    }
}

private extension View {
    func recordingPanel() -> some View {
        background { DetailPanelBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
