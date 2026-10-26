import SwiftUI
import AppKit

/// Uses a native table for selection, keyboard navigation and double-clicks.
/// Reveals the initial channel before interaction so rows stay put during clicks.
struct ChannelChoiceList: NSViewRepresentable {
    let items: [StreamChoice]
    @Binding var selectedID: String?
    let currentID: String?
    let revealID: String?
    let switchMHz: Double
    let activate: (StreamChoice) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("channel"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 44
        table.autoresizingMask = [.width]
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClick(_:))
        table.setAccessibilityLabel(L10n.text("channelCatalog"))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.synchronizing = true
        let revision = items.map { [$0.id, $0.name, details($0), $0.service.encrypted == true ? "encrypted" : ""].joined(separator: "\n") }
            .joined(separator: "\n") + "\n" + (currentID ?? "") + "\n" + L10n.language.rawValue
        if coordinator.revision != revision {
            coordinator.revision = revision
            table.reloadData()
        }
        let index = items.firstIndex { $0.id == selectedID }
        if table.selectedRow != (index ?? -1) {
            table.selectRowIndexes(index.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        }
        coordinator.synchronizing = false
        table.setAccessibilityLabel(L10n.text("channelCatalog"))
        if let revealID, coordinator.revealedID != revealID,
           let row = items.firstIndex(where: { $0.id == revealID }) {
            coordinator.revealedID = revealID
            DispatchQueue.main.async { [weak table, weak coordinator] in
                guard let table, coordinator?.revealedID == revealID else { return }
                table.layoutSubtreeIfNeeded()
                table.scrollRowToVisible(row)
            }
        }
    }

    private func details(_ item: StreamChoice) -> String {
        [item.service.network, item.multiplex?.summary(switchMHz: switchMHz) ?? item.service.multiplex]
            .compactMap { $0 }.joined(separator: " · ")
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ChannelChoiceList
        var revision: String?
        var revealedID: String?
        var synchronizing = false
        init(_ parent: ChannelChoiceList) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("channelRow")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ChannelCell ?? ChannelCell()
            cell.identifier = identifier
            let item = parent.items[row]
            cell.name.stringValue = item.name
            cell.details.stringValue = parent.details(item)
            let encrypted = item.service.encrypted == true
            cell.encryption.isHidden = !encrypted
            cell.encryption.toolTip = L10n.text("encryptedStream")
            cell.encryption.setAccessibilityLabel(L10n.text("encryptedStream"))
            cell.toolTip = [item.name, cell.details.stringValue, encrypted ? L10n.text("encryptedStream") : nil]
                .compactMap { $0 }.joined(separator: "\n")
            cell.check.isHidden = item.id != parent.currentID
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let table = notification.object as? NSTableView else { return }
            parent.selectedID = parent.items.indices.contains(table.selectedRow) ? parent.items[table.selectedRow].id : nil
        }

        @objc func doubleClick(_ table: NSTableView) {
            guard parent.items.indices.contains(table.clickedRow) else { return }
            parent.activate(parent.items[table.clickedRow])
        }
    }

    final class ChannelCell: NSTableCellView {
        let name = NSTextField(labelWithString: "")
        let details = NSTextField(labelWithString: "")
        let check = NSImageView()
        let encryption = NSImageView()

        override var backgroundStyle: NSView.BackgroundStyle {
            didSet {
                encryption.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
            }
        }

        init() {
            super.init(frame: .zero)
            name.font = .systemFont(ofSize: 13, weight: .medium)
            details.font = .systemFont(ofSize: 11)
            details.textColor = .secondaryLabelColor
            for label in [name, details] {
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
            }
            check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            check.contentTintColor = .controlAccentColor
            encryption.image = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: L10n.text("encryptedStream"))?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            encryption.contentTintColor = .secondaryLabelColor
            encryption.setAccessibilityElement(true)
            encryption.setContentCompressionResistancePriority(.required, for: .horizontal)
            encryption.isHidden = true
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let title = NSStackView(views: [name, encryption])
            title.orientation = .horizontal
            title.alignment = .centerY
            title.spacing = 6
            title.detachesHiddenViews = true
            title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let labels = NSStackView(views: [title, details])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 3
            for view in [labels, check] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            NSLayoutConstraint.activate([
                labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(equalTo: check.leadingAnchor, constant: -8),
                title.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
                details.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
                encryption.widthAnchor.constraint(equalToConstant: 14), encryption.heightAnchor.constraint(equalToConstant: 12),
                check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                check.centerYAnchor.constraint(equalTo: centerYAnchor),
                check.widthAnchor.constraint(equalToConstant: 16), check.heightAnchor.constraint(equalToConstant: 16)
            ])
            textField = name
        }

        required init?(coder: NSCoder) { nil }
    }
}
