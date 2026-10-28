import SwiftUI

/// Draft edits are local to the sheet until Apply; the original bytes are never changed.
struct ArtworkCropEditor: View {
    @ObservedObject var model: ProjectModel
    let original: NSImage
    @State private var draft: ArtworkCrop
    @State private var dragOrigin: ArtworkCrop?
    @State private var pinchOrigin: Double?
    @Environment(\.dismiss) private var dismiss
    private let side = 400.0

    init(model: ProjectModel, original: NSImage) {
        self.model = model
        self.original = original
        _draft = State(
            initialValue: (model.project.artworkCrop ?? ArtworkCrop()).clamped(
                width: original.size.width, height: original.size.height))
    }

    private var width: Double { return original.size.width }
    private var height: Double { return original.size.height }
    private var scale: Double { return side / min(width, height) * draft.zoom }
    private var radius: Double { return draft.previewRadius(width: width, height: height, previewSide: side) }

    private var radiusBinding: Binding<Double> {
        return Binding(
            get: { draft.cornerRadius },
            set: { value in
                draft.cornerRadius = value.isFinite ? min(max(value, 0), 800) : 8
            })
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Crop Album Artwork").font(.title2.bold())
            Text("Drag to pan. Use the slider or pinch to zoom.").foregroundStyle(.secondary)
            ZStack {
                Color.black
                Image(nsImage: original).resizable()
                    .frame(width: width * scale, height: height * scale)
                    .offset(
                        x: (0.5 - draft.centerX) * width * scale, y: (0.5 - draft.centerY) * height * scale)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.8), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let origin = dragOrigin ?? draft
                        if dragOrigin == nil { dragOrigin = origin }
                        draft = ArtworkCrop(
                            centerX: origin.centerX - gesture.translation.width / (width * scale),
                            centerY: origin.centerY - gesture.translation.height / (height * scale),
                            zoom: draft.zoom, cornerRadius: draft.cornerRadius
                        )
                        .clamped(width: width, height: height)
                    }.onEnded { _ in dragOrigin = nil }
            )
            .simultaneousGesture(
                MagnifyGesture().onChanged { value in
                    // Incremental magnification preserves the pan center while constraining the square.
                    let origin = pinchOrigin ?? draft.zoom
                    if pinchOrigin == nil { pinchOrigin = origin }
                    draft.zoom = min(max(value.magnification * origin, 0.1), 20)
                    draft = draft.clamped(width: width, height: height)
                }.onEnded { _ in pinchOrigin = nil })
            HStack {
                Text("Zoom")
                Slider(
                    value: Binding(
                        get: { draft.zoom },
                        set: { value in
                            draft.zoom = value
                            draft = draft.clamped(width: width, height: height)
                        }), in: 0.1...20)
                Text(String(format: "%.1f×", draft.zoom)).monospacedDigit().frame(width: 45)
            }
            HStack {
                Text("Corner radius")
                Slider(value: radiusBinding, in: 0...800)
                TextField("Radius", value: radiusBinding, format: .number.precision(.fractionLength(0)))
                    .frame(width: 55)
                Text("px")
            }.help("Radius in exported artwork pixels. Rounded corners are transparent.")
            HStack {
                Button("Reset") { draft = ArtworkCrop() }
                Button("Remove Crop") {
                    model.project.artworkCrop = nil
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    model.project.artworkCrop = draft.clamped(width: width, height: height)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 520)
    }
}
