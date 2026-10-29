import AppKit
import SwiftUI

@main
struct NetMDTXApp: App {
    @NSApplicationDelegateAdaptor(TXAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Keeps monitoring alive independently of the menu or track-list window visibility.
@MainActor
final class TXAppDelegate: NSObject, NSApplicationDelegate {
    private let library = TXLibrary()
    private let splash = StartupSplash()
    private var statusItem: NSStatusItem?
    private var window: TXWindowController?
    private var monitoring: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = VendorCredits.applicationIcon
        NSApp.dockTile.display()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "NetMD TX")
        let menu = NSMenu()
        let show = menu.addItem(withTitle: "Show MiniDisc", action: #selector(showDisc), keyEquivalent: "")
        show.target = self
        let about = menu.addItem(withTitle: "About NetMD TX", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit NetMD TX", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        statusItem = item
        splash.show(applicationName: "NetMD TX")
        monitoring = Task { [weak self] in
            guard let self else { return }
            await library.monitorAttachments { self.showDisc() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitoring?.cancel()
        splash.close()
    }

    @objc private func showAbout() {
        VendorCredits.showAbout(
            applicationName: "NetMD TX", summary: "Transfer and manage MiniDisc recordings.")
    }

    @objc private func showDisc() {
        if window == nil { window = TXWindowController(library: library) }
        window?.showWindow(nil)
        window?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
