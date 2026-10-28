import Foundation

/// Editable square canvas: zooming out or panning beyond the image leaves black padding.
struct ArtworkCrop: Codable, Equatable {
    var centerX: Double
    var centerY: Double
    var zoom: Double
    var cornerRadius: Double

    init(centerX: Double = 0.5, centerY: Double = 0.5, zoom: Double = 1, cornerRadius: Double = 8) {
        self.centerX = centerX
        self.centerY = centerY
        self.zoom = zoom
        self.cornerRadius = cornerRadius
    }

    private enum CodingKeys: String, CodingKey { case centerX, centerY, zoom, cornerRadius }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        centerX = try values.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5
        centerY = try values.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5
        zoom = try values.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        cornerRadius = try values.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 8
    }

    func clamped(width: Double, height: Double) -> ArtworkCrop {
        let zoom = zoom.isFinite ? min(max(zoom, 0.1), 20) : 1
        let side = min(width, height) / zoom
        let halfX = side / max(1, width) / 2
        let halfY = side / max(1, height) / 2
        return ArtworkCrop(
            centerX: min(max(centerX.isFinite ? centerX : 0.5, -halfX), 1 + halfX),
            centerY: min(max(centerY.isFinite ? centerY : 0.5, -halfY), 1 + halfY), zoom: zoom,
            cornerRadius: cornerRadius.isFinite ? min(max(cornerRadius, 0), 800) : 8)
    }

    func rectangle(width: Double, height: Double) -> CGRect {
        let crop = clamped(width: width, height: height)
        let side = min(width, height) / crop.zoom
        return CGRect(
            x: crop.centerX * width - side / 2, y: crop.centerY * height - side / 2, width: side, height: side
        )
    }

    func outputSide(width: Double, height: Double) -> Double {
        return max(1, min(1600, floor(rectangle(width: width, height: height).width)))
    }

    func previewRadius(width: Double, height: Double, previewSide: Double) -> Double {
        let output = outputSide(width: width, height: height)
        return min(max(cornerRadius, 0), output / 2) * previewSide / output
    }
}
