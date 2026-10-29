import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// Adapts the MacroPad/IIgs image search to select original data for nondestructive artwork.
@MainActor
final class ArtworkSearchController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate,
    NSTextFieldDelegate
{
    private var window: NSWindow?
    private var results: WKWebView?
    private var searchPage: WKWebView?
    private let query = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "Search for an artist, album or concert.")
    private let preview = SearchArtworkCropView()
    private let zoom = NSSlider(value: 1, minValue: 0.1, maxValue: 20, target: nil, action: nil)
    private let cornerRadius = NSSlider(value: 8, minValue: 0, maxValue: 800, target: nil, action: nil)
    private let cornerLabel = NSTextField(string: "8")
    private let zoomLabel = NSTextField(labelWithString: "1.0×")
    private let fullImage = NSButton(title: "Use Full Image", target: nil, action: nil)
    private let use = NSButton(title: "Use This Crop", target: nil, action: nil)
    private var selectedData: Data?
    private var requestID = 0
    private var searchQuery = ""
    private var scheduledSearch: Task<Void, Never>?
    private var activeSearchNavigation: WKNavigation?
    private var gridReady = false
    private var pendingResults: [String] = []
    private var download: ArtworkDownload?
    private var completion: ((Data, ArtworkCrop?) -> Void)?
    var onClose: (() -> Void)?
    var canUseSelection: () -> Bool = { true }

    func show(initialQuery: String, completion: @escaping (Data, ArtworkCrop?) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.completion = completion
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 678),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Search Album Artwork"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        guard let content = window.contentView else { return }
        let root = NSView(frame: NSRect(x: 0, y: 28, width: 1000, height: 650))
        content.addSubview(root)
        addAttribution(to: content)
        query.stringValue = initialQuery
        query.placeholderString = "Artist, album or concert"
        query.frame = NSRect(x: 20, y: 600, width: 520, height: 28)
        query.cell?.sendsActionOnEndEditing = false
        query.delegate = self
        query.target = self
        query.action = #selector(search(_:))
        root.addSubview(query)
        let search = NSButton(title: "Search", target: self, action: #selector(search(_:)))
        search.bezelStyle = .rounded
        search.frame = NSRect(x: 550, y: 597, width: 90, height: 32)
        root.addSubview(search)
        let gridConfiguration = WKWebViewConfiguration()
        gridConfiguration.websiteDataStore = .nonPersistent()
        gridConfiguration.userContentController.add(self, name: "iconImage")
        let grid = WKWebView(
            frame: NSRect(x: 20, y: 20, width: 620, height: 560), configuration: gridConfiguration)
        grid.navigationDelegate = self
        results = grid
        root.addSubview(grid)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "iconResults")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: ArtworkSearchPage.collectorScript, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        let collector = WKWebView(frame: grid.bounds, configuration: configuration)
        collector.navigationDelegate = self
        searchPage = collector
        preview.frame = NSRect(x: 665, y: 250, width: 310, height: 310)
        preview.onCropChange = { [weak self] crop in
            self?.zoom.doubleValue = crop.zoom
            self?.zoomLabel.stringValue = String(format: "%.1f×", crop.zoom)
            self?.cornerRadius.doubleValue = crop.cornerRadius
            self?.cornerLabel.stringValue = String(format: "%.0f", crop.cornerRadius)
        }
        root.addSubview(preview)
        let zoomTitle = NSTextField(labelWithString: "Zoom")
        zoomTitle.frame = NSRect(x: 665, y: 210, width: 42, height: 24)
        root.addSubview(zoomTitle)
        zoom.frame = NSRect(x: 708, y: 210, width: 205, height: 24)
        zoom.target = self
        zoom.action = #selector(zoomChanged(_:))
        zoom.isEnabled = false
        root.addSubview(zoom)
        zoomLabel.frame = NSRect(x: 925, y: 210, width: 50, height: 24)
        root.addSubview(zoomLabel)
        let radiusTitle = NSTextField(labelWithString: "Corners")
        radiusTitle.frame = NSRect(x: 665, y: 175, width: 55, height: 24)
        root.addSubview(radiusTitle)
        cornerRadius.frame = NSRect(x: 725, y: 175, width: 180, height: 24)
        cornerRadius.target = self
        cornerRadius.action = #selector(radiusChanged(_:))
        cornerRadius.isEnabled = false
        cornerRadius.toolTip = "Radius in exported artwork pixels. Corners are transparent."
        root.addSubview(cornerRadius)
        cornerLabel.frame = NSRect(x: 915, y: 175, width: 42, height: 24)
        cornerLabel.isEnabled = false
        cornerLabel.target = self
        cornerLabel.action = #selector(radiusTextChanged(_:))
        cornerLabel.setAccessibilityLabel("Corner radius in pixels")
        root.addSubview(cornerLabel)
        let units = NSTextField(labelWithString: "px")
        units.frame = NSRect(x: 960, y: 175, width: 18, height: 24)
        root.addSubview(units)
        status.frame = NSRect(x: 665, y: 565, width: 310, height: 32)
        status.lineBreakMode = .byWordWrapping
        root.addSubview(status)
        let detail = NSTextField(
            wrappingLabelWithString:
                "Drag to pan. Zoom out for black padding. Crops stay editable."
        )
        detail.frame = NSRect(x: 665, y: 135, width: 310, height: 32)
        root.addSubview(detail)
        let local = NSButton(title: "Choose Local Image…", target: self, action: #selector(chooseLocal(_:)))
        local.bezelStyle = .rounded
        local.frame = NSRect(x: 665, y: 100, width: 310, height: 32)
        root.addSubview(local)
        use.target = self
        use.action = #selector(useSelection(_:))
        use.bezelStyle = .rounded
        use.frame = NSRect(x: 665, y: 57, width: 310, height: 32)
        use.isEnabled = false
        root.addSubview(use)
        fullImage.target = self
        fullImage.action = #selector(useFullImage(_:))
        fullImage.bezelStyle = .rounded
        fullImage.frame = NSRect(x: 665, y: 17, width: 310, height: 32)
        fullImage.isEnabled = false
        root.addSubview(fullImage)
        grid.loadHTMLString(
            ArtworkSearchPage.html(searchingLabel: "Enter an artist, album or concert to search."),
            baseURL: nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.search(nil) }
    }

    private func addAttribution(to content: NSView) {
        let separator = NSBox(frame: NSRect(x: 0, y: 27, width: content.bounds.width, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width]
        content.addSubview(separator)
        let text = "Artwork search powered by DuckDuckGo"
        let attribution = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        attribution.addAttributes(
            [
                .link: URL(string: "https://duckduckgo.com/")!,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: (text as NSString).range(of: "DuckDuckGo"))
        let label = NSTextField(labelWithAttributedString: attribution)
        label.frame = NSRect(x: 12, y: 5, width: content.bounds.width - 24, height: 18)
        label.autoresizingMask = [.width]
        label.isSelectable = true
        label.allowsEditingTextAttributes = true
        content.addSubview(label)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === query else { return }
        scheduledSearch?.cancel()
        searchPage?.stopLoading()
        activeSearchNavigation = nil
        searchQuery = ""
        clearSelection()
        pendingResults = []
        gridReady = false
        let text = query.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = text.isEmpty ? "Enter an artist, album or concert to search." : "Waiting for your query…"
        status.stringValue = label
        results?.loadHTMLString(ArtworkSearchPage.html(searchingLabel: label), baseURL: nil)
        guard !text.isEmpty else { return }
        scheduledSearch = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, let self, self.window != nil else { return }
            self.search(nil)
        }
    }

    @objc private func search(_ sender: Any?) {
        scheduledSearch?.cancel()
        scheduledSearch = nil
        let text = query.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status.stringValue = "Enter an artist, album or concert."
            return
        }
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text), URLQueryItem(name: "iax", value: "images"),
            URLQueryItem(name: "ia", value: "images"),
        ]
        guard let url = components?.url else { return }
        clearSelection()
        searchQuery = text
        gridReady = false
        pendingResults = []
        status.stringValue = "Searching DuckDuckGo Images…"
        results?.loadHTMLString(ArtworkSearchPage.html(searchingLabel: "Searching for images…"), baseURL: nil)
        activeSearchNavigation = searchPage?.load(URLRequest(url: url))
    }

    private func clearSelection() {
        requestID += 1
        download?.cancel()
        download = nil
        selectedData = nil
        preview.image = nil
        use.isEnabled = false
        fullImage.isEnabled = false
        zoom.isEnabled = false
        cornerRadius.isEnabled = false
        cornerLabel.isEnabled = false
    }

    @objc private func zoomChanged(_ sender: NSSlider) { preview.setZoom(sender.doubleValue) }

    @objc private func radiusChanged(_ sender: NSSlider) { preview.setCornerRadius(sender.doubleValue) }

    @objc private func radiusTextChanged(_ sender: NSTextField) {
        preview.setCornerRadius(sender.doubleValue)
    }

    private func updateResults() {
        let labeled = pendingResults.enumerated().map {
            ["url": $0.element, "label": "Select image \($0.offset + 1)"]
        }
        guard gridReady, let data = try? JSONSerialization.data(withJSONObject: labeled),
            let json = String(data: data, encoding: .utf8)
        else { return }
        results?.evaluateJavaScript("window.addResults(\(json))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === results {
            gridReady = true
            updateResults()
        } else if webView === searchPage, navigation === activeSearchNavigation, !searchQuery.isEmpty,
            let url = webView.url,
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value == searchQuery
        {
            searchPage?.evaluateJavaScript("collectImages()", completionHandler: nil)
            if pendingResults.isEmpty {
                status.stringValue = "If no images appear, try another query or choose a local image."
            }
        }
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        guard webView === searchPage, navigation === activeSearchNavigation, !searchQuery.isEmpty,
            (error as NSError).code != NSURLErrorCancelled
        else { return }
        status.stringValue = "Search unavailable. Try again or choose a local image."
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        if message.name == "iconResults" {
            guard let body = message.body as? [String: Any], body["query"] as? String == searchQuery,
                let urls = body["urls"] as? [String], !urls.isEmpty
            else { return }
            pendingResults = urls
            updateResults()
            status.stringValue = "Select an image to preview it."
            return
        }
        guard message.name == "iconImage", !searchQuery.isEmpty,
            searchQuery == query.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            let value = message.body as? String
        else { return }
        clearSelection()
        let selectedID = requestID
        if value.hasPrefix("data:image") {
            guard let payload = value.split(separator: ",", maxSplits: 1).last,
                payload.utf8.count <= ArtworkDownload.byteLimit / 3 * 4 + 4,
                let data = Data(base64Encoded: String(payload))
            else {
                status.stringValue = "That image could not be loaded."
                return
            }
            select(data)
        } else if let url = URL(string: value), url.scheme == "https" {
            status.stringValue = "Loading selected image…"
            download = ArtworkDownload(url: url) { [weak self] result in
                guard let self, self.requestID == selectedID else { return }
                self.download = nil
                switch result {
                case .success(let data): self.select(data)
                case .failure(let error): self.status.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func select(_ data: Data) {
        do {
            try Self.validateImage(data)
            preview.image = try ArtworkProcessor.preview(data, crop: nil)
            selectedData = data
            use.isEnabled = true
            fullImage.isEnabled = true
            zoom.isEnabled = true
            cornerRadius.isEnabled = true
            cornerLabel.isEnabled = true
            status.stringValue = "Drag and zoom to choose the crop."
        } catch { status.stringValue = error.localizedDescription }
    }

    static func validateImage(_ data: Data) throws {
        guard data.count <= ArtworkDownload.byteLimit else {
            throw BootleggerError.message("Choose an image smaller than 30 MB.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0, height > 0
        else { throw BootleggerError.message("That image could not be decoded. Try another result.") }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= 100_000_000 else {
            throw BootleggerError.message("Choose an image smaller than 100 megapixels.")
        }
    }

    @objc private func chooseLocal(_ sender: Any?) {
        scheduledSearch?.cancel()
        scheduledSearch = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        clearSelection()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ArtworkDownload.byteLimit else {
                throw BootleggerError.message("Choose an image smaller than 30 MB.")
            }
            select(try Data(contentsOf: url))
        } catch { status.stringValue = error.localizedDescription }
    }

    @objc private func useFullImage(_ sender: Any?) { applySelection(crop: nil) }

    @objc private func useSelection(_ sender: Any?) { applySelection(crop: preview.crop) }

    private func applySelection(crop: ArtworkCrop?) {
        guard let selectedData else { return }
        guard canUseSelection() else {
            status.stringValue = "Wait for the current project operation to finish, then use this image."
            return
        }
        completion?(selectedData, crop)
        window?.close()
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        scheduledSearch?.cancel()
        scheduledSearch = nil
        searchQuery = ""
        activeSearchNavigation = nil
        clearSelection()
        results?.stopLoading()
        searchPage?.stopLoading()
        results?.configuration.userContentController.removeScriptMessageHandler(forName: "iconImage")
        searchPage?.configuration.userContentController.removeScriptMessageHandler(forName: "iconResults")
        results?.navigationDelegate = nil
        searchPage?.navigationDelegate = nil
        completion = nil
        window = nil
        onClose?()
        onClose = nil
    }
}
