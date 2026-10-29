import AppKit
import Combine
import SwiftUI

/// Owns the native unified toolbar and keeps the title synchronized with the inserted disc.
@MainActor
final class TXWindowController: NSWindowController, NSToolbarDelegate {
    private let library: TXLibrary
    private var subscriptions: Set<AnyCancellable> = []
    private var options: NSPopover?
    private var refreshItem: NSToolbarItem?
    private var renameItem: NSToolbarItem?
    private var settingsButton: NSButton?
    private static let renameID = NSToolbarItem.Identifier("tx.renameAlbum")
    private static let refreshID = NSToolbarItem.Identifier("tx.refresh")
    private static let settingsID = NSToolbarItem.Identifier("tx.settings")

    init(library: TXLibrary) {
        self.library = library
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: TXDiscView(library: library))
        let toolbar = NSToolbar(identifier: "NetMDTX.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.center()
        library.controller.objectWillChange
            .merge(with: library.objectWillChange, library.extraction.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateWindow() }.store(in: &subscriptions)
        updateWindow()
    }

    required init?(coder: NSCoder) { return nil }

    private func updateWindow() {
        let disc = library.controller.disc
        let device = disc?.device ?? library.controller.devices.first?.name ?? "NetMD TX"
        window?.title = device + (disc.map { " — \($0.title.isEmpty ? "Untitled MD" : $0.title)" } ?? "")
        if library.isOccupied { options?.close() }
        if let toolbar = window?.toolbar {
            let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.renameID }
            if disc?.writable == true && index == nil {
                toolbar.insertItem(withItemIdentifier: Self.renameID, at: 1)
            }
            if disc?.writable != true, let index { toolbar.removeItem(at: index) }
        }
        renameItem?.isEnabled = !library.isOccupied && disc?.writable == true
        refreshItem?.isEnabled = !library.isOccupied
        settingsButton?.isEnabled = !library.isOccupied
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace] + (library.controller.disc?.writable == true ? [Self.renameID] : [])
            + [Self.refreshID, Self.settingsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, Self.renameID, Self.refreshID, Self.settingsID]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.autovalidates = false
        if itemIdentifier == Self.renameID {
            item.label = "Rename Album"
            item.toolTip = "Rename the MiniDisc album"
            item.image = NSImage(
                systemSymbolName: "square.and.pencil", accessibilityDescription: "Rename Album")
            item.action = #selector(renameAlbum)
            item.isEnabled = !library.isOccupied && library.controller.disc?.writable == true
            renameItem = item
        } else if itemIdentifier == Self.refreshID {
            item.label = "Refresh"
            item.toolTip = "Read the inserted MiniDisc"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.action = #selector(refresh)
            refreshItem = item
        } else if itemIdentifier == Self.settingsID {
            item.label = "Settings"
            let button = NSButton(
                image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
                target: self, action: #selector(showSettings(_:)))
            button.bezelStyle = .texturedRounded
            button.toolTip = "Transfer settings"
            item.view = button
            settingsButton = button
        } else {
            return nil
        }
        return item
    }

    @objc private func renameAlbum() {
        guard !library.isOccupied, let disc = library.controller.disc, disc.writable, let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Rename Album"
        alert.informativeText = "The album title will be saved to the MiniDisc."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: disc.title)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.library.rename(title: field.stringValue, track: nil, disc: disc)
            }
        }
    }

    @objc private func refresh() { Task { await library.controller.refresh() } }

    @objc private func showSettings(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TXSettingsView(library: library))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        options = popover
    }
}
