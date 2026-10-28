import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Project artwork stays original; rendering a preview never re-encodes the source.
enum ArtworkProcessor {
    static func originalImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue),
                ] as CFDictionary)
        else {
            throw BootleggerError.message("The artwork image could not be decoded.")
        }
        return image
    }

    static func filenameExtension(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source), let imageType = UTType(type as String)
        else { return "image" }
        return imageType.preferredFilenameExtension ?? "image"
    }

    static func renderedImage(_ data: Data, crop: ArtworkCrop?) throws -> CGImage {
        let original = try originalImage(data)
        let sourceWidth = Double(original.width)
        let sourceHeight = Double(original.height)
        let frame =
            crop?.rectangle(width: sourceWidth, height: sourceHeight)
            ?? CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        let scale = min(1, 1600 / max(frame.width, frame.height))
        let width = max(1, Int(floor(frame.width * scale)))
        let height = max(1, Int(floor(frame.height * scale)))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw BootleggerError.message("The artwork canvas could not be created.")
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let crop {
            let radius = min(max(crop.cornerRadius, 0), Double(min(width, height)) / 2)
            context.addPath(
                CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            context.setFillColor(NSColor.black.cgColor)
            context.fill(bounds)
        }
        context.interpolationQuality = .high
        // Crop coordinates are top-left based; Core Graphics drawing is bottom-left based.
        let placement = CGRect(
            x: -frame.minX * scale, y: (frame.maxY - sourceHeight) * scale,
            width: sourceWidth * scale, height: sourceHeight * scale)
        context.draw(original, in: placement)
        guard let image = context.makeImage() else {
            throw BootleggerError.message("The artwork could not be rendered.")
        }
        return image
    }

    static func preview(_ data: Data, crop: ArtworkCrop?) throws -> NSImage {
        let image = try crop == nil ? originalImage(data) : renderedImage(data, crop: crop)
        return NSImage(cgImage: image, size: .zero)
    }

    /// PNG retains rounded/transparent corners. Opaque, square-corner crops can use JPEG.
    static func exportArtwork(_ data: Data, crop: ArtworkCrop?) throws -> EncodedArtwork {
        let image = try renderedImage(data, crop: crop)
        let originalAlpha = try originalImage(data).alphaInfo
        let sourceHasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(originalAlpha)
        let transparent = crop.map { $0.cornerRadius > 0 } ?? sourceHasAlpha
        let type: NSBitmapImageRep.FileType = transparent ? .png : .jpeg
        guard
            let encoded = NSBitmapImageRep(cgImage: image).representation(
                using: type, properties: [.compressionFactor: 0.9])
        else {
            throw BootleggerError.message("The artwork could not be encoded for export.")
        }
        return EncodedArtwork(data: encoded, isPNG: transparent)
    }

    static func exportJPEG(_ data: Data, crop: ArtworkCrop?) throws -> Data {
        let image = try renderedImage(data, crop: crop)
        guard
            let jpeg = NSBitmapImageRep(cgImage: image).representation(
                using: .jpeg, properties: [.compressionFactor: 0.9])
        else {
            throw BootleggerError.message("The artwork could not be encoded for export.")
        }
        return jpeg
    }
}

struct EncodedArtwork {
    let data: Data
    let isPNG: Bool
}
