import AppKit
import SwiftUI

/// A nonblocking, nonactivating acknowledgement panel, dismissed two seconds after launch.
@MainActor
final class StartupSplash {
    fileprivate static let size = NSSize(width: 440, height: 350)
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(applicationName: String) {
        close()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = false
        panel.contentView = Self.makeContent(applicationName: applicationName)
        self.panel = panel
        panel.center()
        panel.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.close()
        }
    }

    fileprivate static func makeContent(applicationName: String) -> NSView {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true
        let icon = NSImageView()
        icon.image = VendorCredits.applicationIcon
        icon.setAccessibilityLabel(applicationName)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 160).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let title = NSTextField(labelWithString: applicationName)
        title.font = .systemFont(ofSize: 25, weight: .bold)
        let thanks = NSTextField(
            wrappingLabelWithString:
                "Made possible open-source software.\nSee About \(applicationName) for thanks and credits."
        )
        thanks.font = .systemFont(ofSize: 13)
        thanks.textColor = .secondaryLabelColor
        thanks.alignment = .center
        thanks.preferredMaxLayoutWidth = 392
        let stack = NSStackView(views: [icon, title, thanks])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return content
    }

    func close() {
        dismissal?.cancel()
        dismissal = nil
        panel?.close()
        panel = nil
    }
}

private struct StartupSplashPreview: NSViewRepresentable {
    let applicationName: String

    func makeNSView(context: Context) -> NSView {
        return StartupSplash.makeContent(applicationName: applicationName)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview("Bootlegger splash") {
    StartupSplashPreview(applicationName: "Bootlegger")
        .frame(width: StartupSplash.size.width, height: StartupSplash.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("NetMD TX splash") {
    StartupSplashPreview(applicationName: "NetMD TX")
        .frame(width: StartupSplash.size.width, height: StartupSplash.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
}
