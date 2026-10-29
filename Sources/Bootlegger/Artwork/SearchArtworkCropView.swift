import AppKit

/// Search preview uses the same normalized, nondestructive crop as the project editor.
@MainActor
final class SearchArtworkCropView: NSView {
    var image: NSImage? {
        didSet {
            setCrop(ArtworkCrop())
            setAccessibilityLabel(image == nil ? "No image yet" : "Artwork crop preview")
        }
    }
    private(set) var crop = ArtworkCrop()
    var onCropChange: ((ArtworkCrop) -> Void)?
    private var dragStart = CGPoint.zero
    private var dragCrop = ArtworkCrop()
    override var isFlipped: Bool { return true }

    func setCrop(_ value: ArtworkCrop) {
        crop = value.clamped(width: Double(image?.size.width ?? 1), height: Double(image?.size.height ?? 1))
        needsDisplay = true
        onCropChange?(crop)
    }

    func setZoom(_ zoom: Double) {
        var value = crop
        value.zoom = zoom
        setCrop(value)
    }

    func setCornerRadius(_ radius: Double) {
        var value = crop
        value.cornerRadius = radius
        setCrop(value)
    }

    private var scale: Double {
        guard let image else { return 1 }
        return max(bounds.width / image.size.width, bounds.height / image.size.height) * crop.zoom
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else {
            drawPlaceholder()
            return
        }
        let radius = crop.previewRadius(
            width: Double(image.size.width), height: Double(image.size.height),
            previewSide: bounds.width)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSColor.black.setFill()
        bounds.fill()
        let rectangle = CGRect(
            x: bounds.midX - crop.centerX * image.size.width * scale,
            y: bounds.midY - crop.centerY * image.size.height * scale,
            width: image.size.width * scale, height: image.size.height * scale)
        image.draw(
            in: rectangle, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawPlaceholder() {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor])))
        if let symbol {
            symbol.draw(
                in: NSRect(x: bounds.midX - 24, y: bounds.midY - 44, width: 48, height: 40),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let title = NSAttributedString(
            string: "No image yet",
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        let size = title.size()
        title.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY + 8))
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCrop = crop
    }

    override func mouseDragged(with event: NSEvent) {
        guard let image else { return }
        let point = convert(event.locationInWindow, from: nil)
        setCrop(
            ArtworkCrop(
                centerX: dragCrop.centerX - (point.x - dragStart.x) / (image.size.width * scale),
                centerY: dragCrop.centerY - (point.y - dragStart.y) / (image.size.height * scale),
                zoom: crop.zoom, cornerRadius: crop.cornerRadius))
    }

    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        setZoom(crop.zoom * (1 + event.magnification))
    }
}
