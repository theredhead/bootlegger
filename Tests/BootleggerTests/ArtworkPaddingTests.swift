import AppKit

@MainActor
enum ArtworkPaddingTests {
    static func run() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<50 {
            for x in 0..<100 {
                bitmap.setColor(
                    NSColor(deviceRed: y < 25 ? 1 : 0, green: 0, blue: y < 25 ? 0 : 1, alpha: 1),
                    atX: x, y: y)
            }
        }
        let original = bitmap.representation(using: .png, properties: [:])!
        let padded = ArtworkCrop(zoom: 0.5, cornerRadius: 8)
        try SmokeTests.require(padded.clamped(width: 100, height: 50).zoom == 0.5, "zoom-out is retained")
        let encoded = try ArtworkProcessor.exportArtwork(original, crop: padded)
        let image = NSBitmapImageRep(data: encoded.data)!
        try SmokeTests.require(
            encoded.isPNG && image.pixelsWide == 100 && image.pixelsHigh == 100,
            "rounded crop exports a square PNG")
        let corner = image.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        let bar = image.colorAt(x: 50, y: 5)!.usingColorSpace(.deviceRGB)!
        try SmokeTests.require(corner.alphaComponent < 0.01, "rounded corner is transparent")
        try SmokeTests.require(
            bar.alphaComponent > 0.99 && bar.redComponent < 0.01 && bar.greenComponent < 0.01
                && bar.blueComponent < 0.01, "zoom-out padding is opaque black")
        let top = NSBitmapImageRep(
            cgImage: try ArtworkProcessor.renderedImage(
                original, crop: ArtworkCrop(centerY: 0.25, zoom: 2, cornerRadius: 0)))
        let bottom = NSBitmapImageRep(
            cgImage: try ArtworkProcessor.renderedImage(
                original, crop: ArtworkCrop(centerY: 0.75, zoom: 2, cornerRadius: 0)))
        let topColor = top.colorAt(x: 12, y: 12)!.usingColorSpace(.deviceRGB)!
        let bottomColor = bottom.colorAt(x: 12, y: 12)!.usingColorSpace(.deviceRGB)!
        try SmokeTests.require(
            topColor.redComponent > 0.9 && bottomColor.blueComponent > 0.9,
            "pan/export coordinates preserve image orientation")
        let opaque = try ArtworkProcessor.exportArtwork(
            original, crop: ArtworkCrop(zoom: 0.5, cornerRadius: 0))
        try SmokeTests.require(!opaque.isPNG, "square opaque crops can use JPEG")
        let legacy = try JSONDecoder().decode(
            ArtworkCrop.self, from: Data(#"{"centerX":0.5,"centerY":0.5,"zoom":1}"#.utf8))
        try SmokeTests.require(legacy.cornerRadius == 8, "old crops receive the default 8px radius")
        let roundTrip = try JSONDecoder().decode(ArtworkCrop.self, from: JSONEncoder().encode(padded))
        try SmokeTests.require(roundTrip == padded, "padding and corner radius survive metadata round trip")
        let view = SearchArtworkCropView(frame: NSRect(x: 0, y: 0, width: 310, height: 310))
        view.image = NSImage(data: original)
        view.setZoom(0.5)
        view.setCornerRadius(12)
        try SmokeTests.require(
            view.crop.zoom == 0.5 && view.crop.cornerRadius == 12, "search crop supports zoom-out and radius")
        view.image = NSImage(data: original)
        try SmokeTests.require(
            view.crop.cornerRadius == 8 && view.crop.zoom == 1, "new image resets zoom and radius")
        print(
            "PASS: zoom-out black padding, transparent PNG corners, radius defaults/persistence and pan orientation."
        )
    }
}
