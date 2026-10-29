import AppKit
import SwiftUI

/// Native table drag sessions provide asynchronous Finder file promises and accept file URLs.
struct TXTrackTable: NSViewRepresentable {
    @ObservedObject var library: TXLibrary
    @ObservedObject var controller = NetMDController.shared
    @ObservedObject var extraction: TXExtraction

    func makeCoordinator() -> Coordinator { return Coordinator(library: library) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TXRenamingTableView()
        table.renameSelection = { [weak coordinator = context.coordinator] table in
            return coordinator?.beginSelectedRename(table) ?? false
        }
        for (id, title, width) in [
            ("handle", "", 26.0), ("number", "#", 44.0), ("title", "Track", 380.0),
            ("mode", "Format", 80.0), ("duration", "Duration", 90.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.rowHeight = 28
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.beginRename(_:))
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.registerForDraggedTypes([.fileURL, TXTrackFilePromise.rowType])
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        table.tableColumns.first { $0.identifier.rawValue == "handle" }?.isHidden =
            controller.disc?.writable != true
        context.coordinator.disc = controller.disc
        context.coordinator.queue = library.queue
        if context.coordinator.isEditing { return }
        let selected = table.selectedRowIndexes
        table.reloadData()
        table.selectRowIndexes(
            IndexSet(selected.filter { $0 < table.numberOfRows }), byExtendingSelection: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        let library: TXLibrary
        var disc: NetMDDisc?
        var queue: [TXQueuedFile] = []
        private var dragBatchID = UUID()
        private var draggedDisc: NetMDDisc?
        private var editingDisc: NetMDDisc?
        private var editingIndex: Int?
        private weak var editingTable: NSTableView?
        var isEditing: Bool { return editingDisc != nil }

        init(library: TXLibrary) { self.library = library }

        func numberOfRows(in tableView: NSTableView) -> Int { return (disc?.tracks.count ?? 0) + queue.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let key = tableColumn?.identifier.rawValue ?? ""
            if key == "handle" {
                guard disc?.writable == true, disc?.tracks.indices.contains(row) == true else { return nil }
                let image = NSImageView()
                image.image = NSImage(
                    systemSymbolName: "line.3.horizontal", accessibilityDescription: "Reorder track")
                image.contentTintColor = .secondaryLabelColor
                image.imageScaling = .scaleNone
                return image
            }
            let text: String
            if let disc, disc.tracks.indices.contains(row) {
                let track = disc.tracks[row]
                switch key {
                case "number": text = String(row + 1)
                case "title": text = track.title.isEmpty ? "Untitled track" : track.title
                case "mode": text = track.mode?.uppercased() ?? "—"
                default: text = ExportPlan.durationLabel(track.duration)
                }
            } else {
                let index = row - (disc?.tracks.count ?? 0)
                guard queue.indices.contains(index) else { return nil }
                let item = queue[index]
                switch key {
                case "number": text = "…"
                case "title": text = item.title
                case "mode": text = "Pending"
                default: text = ExportPlan.durationLabel(item.duration)
                }
            }
            let field = NSTextField(labelWithString: text)
            field.lineBreakMode = .byTruncatingTail
            if key == "title" {
                field.delegate = self
                field.toolTip = disc?.writable == true ? "Double-click to rename this track" : nil
            }
            if key == "duration" { field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }
            let cell = NSTableCellView()
            cell.textField = field
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        @objc func beginRename(_ table: NSTableView) {
            guard table.clickedColumn >= 0,
                table.tableColumns[table.clickedColumn].identifier.rawValue == "title"
            else { return }
            _ = beginRename(row: table.clickedRow, in: table)
        }

        func beginSelectedRename(_ table: NSTableView) -> Bool {
            guard table.selectedRowIndexes.count == 1 else { return false }
            return beginRename(row: table.selectedRow, in: table)
        }

        private func beginRename(row: Int, in table: NSTableView) -> Bool {
            guard !isEditing, !library.isOccupied, let disc, disc.writable,
                disc.tracks.indices.contains(row),
                let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "title" }),
                let field =
                    (table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?
                    .textField
            else { return false }
            editingDisc = disc
            editingIndex = row
            editingTable = table
            field.stringValue = disc.tracks[row].title
            field.isEditable = true
            field.isSelectable = true
            table.window?.makeFirstResponder(field)
            field.selectText(nil)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let snapshot = editingDisc,
                let index = editingIndex
            else { return }
            let title = field.stringValue
            editingDisc = nil
            editingIndex = nil
            field.isEditable = false
            field.isSelectable = false
            if title != snapshot.tracks[index].title {
                library.rename(title: title, track: index, disc: snapshot)
            }
            editingTable?.reloadData()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
            -> Bool
        {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if let field = control as? NSTextField, let snapshot = editingDisc, let index = editingIndex {
                    field.stringValue = snapshot.tracks[index].title
                }
                editingTable?.window?.makeFirstResponder(editingTable)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                editingTable?.window?.makeFirstResponder(editingTable)
                return true
            }
            return false
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard !library.isOccupied, let disc, disc.tracks.indices.contains(row) else { return nil }
            if TXPromisedTrack.supports(disc, index: row) {
                return library.extraction.provider(
                    for: TXPromisedTrack(
                        disc: disc, index: row, convertToWAV: library.convertToWAV, batchID: dragBatchID),
                    row: disc.writable ? row : nil)
            }
            guard disc.writable else { return nil }
            let item = NSPasteboardItem()
            item.setString(String(row), forType: TXTrackFilePromise.rowType)
            return item
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet
        ) {
            guard let disc else { return }
            draggedDisc = disc
            let count = rowIndexes.filter { TXPromisedTrack.supports(disc, index: $0) }.count
            library.extraction.prepareBatch(id: dragBatchID, count: count)
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint, operation: NSDragOperation
        ) {
            dragBatchID = UUID()
            draggedDisc = nil
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
            proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard !library.isOccupied, controllerReady else { return [] }
            if info.draggingSource as? NSTableView === tableView {
                guard let order = proposedOrder(info, insertion: row),
                    order != Array(0..<(disc?.tracks.count ?? 0))
                else { return [] }
                tableView.setDropRow(row, dropOperation: .above)
                return .move
            }
            guard !fileURLs(info).isEmpty else { return [] }
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }

        func tableView(
            _ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
            row: Int, dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard !library.isOccupied, controllerReady else { return false }
            if info.draggingSource as? NSTableView === tableView {
                guard let order = proposedOrder(info, insertion: row), let snapshot = draggedDisc else {
                    return false
                }
                return library.reorder(order: order, disc: snapshot)
            }
            let urls = fileURLs(info)
            guard !library.isOccupied, controllerReady, !urls.isEmpty else { return false }
            return library.importFiles(urls)
        }

        private func proposedOrder(_ info: NSDraggingInfo, insertion: Int) -> [Int]? {
            guard let disc, draggedDisc?.fingerprint == disc.fingerprint else { return nil }
            let items = info.draggingPasteboard.pasteboardItems ?? []
            let rows = items.compactMap { $0.string(forType: TXTrackFilePromise.rowType).flatMap(Int.init) }
            guard rows.count == items.count else { return nil }
            return TXTrackOrder.moving(IndexSet(rows), to: insertion, count: disc.tracks.count)
        }

        private var controllerReady: Bool {
            return library.controller.disc?.writable == true
        }

        private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
            return info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
    }
}

/// Handles Return only while the table owns keyboard focus; the field editor retains its save/cancel keys.
private final class TXRenamingTableView: NSTableView {
    var renameSelection: ((NSTableView) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if isReturn && modifiers.isEmpty && renameSelection?(self) == true { return }
        super.keyDown(with: event)
    }
}
