import AppKit

@main
@MainActor
struct BootleggerApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.mainMenu = makeMenu()
        _ = NSDocumentController.shared
        application.run()
        withExtendedLifetime(delegate) {}
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func section(_ title: String, items: [(String, Selector?, String)]) {
            let root = NSMenuItem()
            root.title = title
            let submenu = NSMenu(title: title)
            for (name, action, key) in items {
                if name == "-" {
                    submenu.addItem(.separator())
                } else {
                    submenu.addItem(withTitle: name, action: action, keyEquivalent: key)
                }
            }
            root.submenu = submenu
            menu.addItem(root)
        }
        section(
            "Bootlegger",
            items: [
                ("About Bootlegger", #selector(AppDelegate.showAbout(_:)), ""),
                ("-", nil, ""),
                ("Hide Bootlegger", #selector(NSApplication.hide(_:)), "h"),
                ("Quit Bootlegger", #selector(NSApplication.terminate(_:)), "q"),
            ])
        menu.items.first?.submenu?.items.first?.target = NSApplication.shared.delegate
        section(
            "File",
            items: [
                ("New Project", #selector(NSDocumentController.newDocument(_:)), "n"),
                ("Open Project…", #selector(NSDocumentController.openDocument(_:)), "o"),
                ("Import Recording…", #selector(ProjectDocument.importRecordingFromMenu(_:)), "i"),
                ("Export Album…", #selector(ProjectDocument.exportAlbumFromMenu(_:)), "e"),
                ("-", nil, ""),
                ("Close", #selector(NSWindow.performClose(_:)), "w"),
                ("Save", #selector(NSDocument.save(_:)), "s"),
                ("Save As…", #selector(NSDocument.saveAs(_:)), "S"),
            ])
        section(
            "Edit",
            items: [
                ("Undo", Selector(("undo:")), "z"),
                ("Redo", Selector(("redo:")), "Z"),
                ("-", nil, ""),
                ("Cut", #selector(NSText.cut(_:)), "x"),
                ("Copy", #selector(NSText.copy(_:)), "c"),
                ("Paste", #selector(NSText.paste(_:)), "v"),
                ("Select All", #selector(NSText.selectAll(_:)), "a"),
            ])
        section(
            "Artwork",
            items: [
                ("Search Artwork…", #selector(ProjectDocument.searchArtworkFromMenu(_:)), "F"),
                ("Capture Frame", #selector(ProjectDocument.captureArtworkFromMenu(_:)), ""),
                ("Edit Crop…", #selector(ProjectDocument.editArtworkCropFromMenu(_:)), ""),
                ("Remove Crop", #selector(ProjectDocument.removeArtworkCropFromMenu(_:)), ""),
            ])
        section(
            "Tools",
            items: [
                ("Prescan Audio Levels", #selector(ProjectDocument.prescanAudioLevelsFromMenu(_:)), ""),
                ("Cancel Audio Prescan", #selector(ProjectDocument.cancelAudioPrescanFromMenu(_:)), ""),
            ])
        section(
            "Window",
            items: [
                ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
                ("Zoom", #selector(NSWindow.performZoom(_:)), ""),
                ("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
            ])
        NSApplication.shared.windowsMenu = menu.items.last?.submenu
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func showAbout(_ sender: Any?) {
        let bundle = Bundle.main
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Bootlegger",
            .credits: NSAttributedString(
                string:
                    "Turn concert recordings into albums.\nApp: MIT • NetMD helper: GPL-3.0-or-later\nThird-party sources and notices are bundled."
            ),
        ]
        if let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            options[.applicationIcon] = icon
        }
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            options[.applicationVersion] = version
        }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            options[.version] = build
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // This app creates NSApplication itself; explicitly update the live Dock icon as well as bundle metadata.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            NSApplication.shared.applicationIconImage = icon
            NSApplication.shared.dockTile.display()
        } else {
            NSLog("Bootlegger: bundled AppIcon.icns could not be loaded.")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if NSDocumentController.shared.documents.isEmpty {
            do { try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) } catch {
                NSApplication.shared.presentError(error)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let controller = NSDocumentController.shared
        var useCurrentProject = true
        for url in urls {
            if ProjectModel.isRecording(url) {
                do {
                    let document: ProjectDocument
                    if useCurrentProject,
                        let current =
                            (controller.currentDocument
                            ?? application.mainWindow?.windowController?.document
                            ?? (controller.documents.count == 1 ? controller.documents.first : nil))
                            as? ProjectDocument
                    {
                        document = current
                    } else {
                        guard
                            let created = try controller.openUntitledDocumentAndDisplay(true)
                                as? ProjectDocument
                        else { continue }
                        document = created
                    }
                    useCurrentProject = false
                    document.showWindows()
                    document.model.importRecording(from: url)
                } catch { application.presentError(error) }
            } else {
                controller.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { application.presentError(error) }
                }
            }
        }
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { return false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.newDocument(nil) }
        return true
    }
}
