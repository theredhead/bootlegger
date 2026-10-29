import AppKit

/// Shared acknowledgements for the bundled projects and their authors.
@MainActor
enum VendorCredits {
    struct Entry {
        let project: String
        let authors: String
        let url: String
    }

    static let entries: [Entry] = [
        Entry(
            project: "netmd++", authors: "Jo2003 and the Linux MiniDisc contributors",
            url: "https://github.com/Jo2003/netmd_plusplus"),
        Entry(
            project: "ATRACDEnc", authors: "Daniil Cherednik and contributors",
            url: "https://github.com/dcherednik/atracdenc"),
        Entry(
            project: "libgha", authors: "Daniil Cherednik and contributors",
            url: "https://github.com/dcherednik/libgha"),
        Entry(project: "libusb", authors: "Johannes Erdfelt and contributors", url: "https://libusb.info/"),
        Entry(
            project: "libgcrypt & libgpg-error", authors: "Werner Koch and the GnuPG contributors",
            url: "https://gnupg.org/"),
        Entry(
            project: "libsndfile", authors: "Erik de Castro Lopo and the libsndfile team",
            url: "https://libsndfile.github.io/libsndfile/"),
        Entry(
            project: "Kiss FFT", authors: "Mark Borgerding and contributors",
            url: "https://github.com/mborgerding/kissfft"),
        Entry(
            project: "FFmpeg ATRAC DSP", authors: "Maxim Poliakovski and the FFmpeg contributors",
            url: "https://ffmpeg.org/"),
    ]

    private static var aboutPanel: NSPanel?

    static var applicationIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            return icon
        }
        return NSApp.applicationIconImage
    }

    static func showAbout(applicationName: String, summary: String) {
        if let aboutPanel {
            aboutPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "About \(applicationName)"
        panel.isReleasedWhenClosed = false
        let content = NSView()
        panel.contentView = content
        let icon = NSImageView()
        icon.image = applicationIcon
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let title = label(applicationName, font: .systemFont(ofSize: 23, weight: .bold))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionLabel = label("Version \(version) (\(build))", font: .systemFont(ofSize: 12))
        versionLabel.textColor = .secondaryLabelColor
        let thanks = label("With thanks to", font: .systemFont(ofSize: 14, weight: .semibold))
        var views: [NSView] = [icon, title, versionLabel, label(summary), thanks]
        for entry in entries {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let text = NSMutableAttributedString(
                string: entry.project + "\n" + entry.authors,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ])
            text.addAttributes(
                [
                    .link: URL(string: entry.url)!, .foregroundColor: NSColor.linkColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                ], range: (text.string as NSString).range(of: entry.project))
            let credit = NSTextField(wrappingLabelWithString: "")
            credit.attributedStringValue = text
            credit.preferredMaxLayoutWidth = 552
            credit.isSelectable = true
            credit.allowsEditingTextAttributes = true
            views.append(credit)
        }
        let licenses = label(
            "App: MIT • NetMD helper: GPL-3.0-or-later\nIncludes LGPL libraries and BSD components.\nFull copyright notices, licenses and corresponding source are bundled.",
            font: .systemFont(ofSize: 11))
        licenses.textColor = .secondaryLabelColor
        views.append(licenses)
        if let resources = Bundle.main.resourceURL {
            let directory = resources.appendingPathComponent("Licenses")
            let destination =
                FileManager.default.fileExists(atPath: directory.path)
                ? directory : resources.appendingPathComponent("NetMDSources")
            let link = NSTextField(
                labelWithAttributedString: NSAttributedString(
                    string: "Third-party licenses and source",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11), .link: destination,
                        .foregroundColor: NSColor.linkColor,
                    ]))
            link.isSelectable = true
            link.allowsEditingTextAttributes = true
            views.append(link)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 552),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 600, height: ceil(stack.fittingSize.height) + 48))
        aboutPanel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func label(_ text: String, font: NSFont = .systemFont(ofSize: 12)) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.alignment = .center
        label.preferredMaxLayoutWidth = 552
        return label
    }
}
