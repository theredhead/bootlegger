import SwiftUI

struct AudioLevelView: View {
    @ObservedObject var model: ProjectModel
    @ObservedObject var playback: Playback
    @ObservedObject var levels: AudioLevels
    @State private var zoom = log10(5.0)

    private var halfWindow: Double { return pow(10, zoom) }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Audio level").font(.caption.bold())
                if levels.isPrescanning {
                    ProgressView(value: levels.prescanProgress).frame(width: 70)
                    Text("Prescanning \(Int(levels.prescanProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel", action: levels.cancelPrescan).controlSize(.mini)
                } else if levels.hasFullCache {
                    Text("Concert cached").font(.caption).foregroundStyle(.secondary)
                } else if let error = levels.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if levels.samples == nil {
                    Text("Reading audio…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "±%.2f s", halfWindow)).font(.system(.caption, design: .monospaced))
                Slider(value: $zoom, in: log10(0.1)...log10(5.0)).frame(width: 110)
                    .accessibilityLabel("Audio display time span")
                    .help("Zoom from five seconds to 0.1 second on each side of the cursor")
            }
            GeometryReader { geometry in
                Canvas { context, size in
                    let lower = playback.position - halfWindow
                    let span = halfWindow * 2
                    if let song = model.selectedSong {
                        let start = max(0, (song.start - lower) / span * size.width)
                        let end = min(size.width, (song.end - lower) / span * size.width)
                        if end > start {
                            context.fill(
                                Path(CGRect(x: start, y: 0, width: end - start, height: size.height)),
                                with: .color(.accentColor.opacity(0.1)))
                        }
                    }
                    var waveform = Path()
                    if let samples = levels.samples {
                        for pixel in 0..<max(1, Int(size.width)) {
                            let from = lower + Double(pixel) / size.width * span
                            let to = lower + Double(pixel + 1) / size.width * span
                            let peak = Double(samples.peak(from: from, to: to))
                            let height = max(0.5, peak * (size.height / 2 - 2))
                            waveform.move(to: CGPoint(x: Double(pixel), y: size.height / 2 - height))
                            waveform.addLine(to: CGPoint(x: Double(pixel), y: size.height / 2 + height))
                        }
                    }
                    context.stroke(waveform, with: .color(.accentColor), lineWidth: 1)
                    var cursor = Path()
                    cursor.move(to: CGPoint(x: size.width / 2, y: 0))
                    cursor.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    context.stroke(cursor, with: .color(.primary), lineWidth: 1)
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture { point in
                    playback.seek(
                        playback.position + (point.x / max(1, geometry.size.width) - 0.5) * halfWindow * 2)
                }
                .accessibilityLabel("Audio amplitude around the playhead; click to seek")
            }
            HStack {
                Text(Timestamp.string(max(0, playback.position - halfWindow)))
                Spacer()
                Text(Timestamp.string(playback.position))
                Spacer()
                Text(Timestamp.string(min(playback.duration, playback.position + halfWindow)))
            }.font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }
        .task(id: requestKey) {
            if let url = model.sourceURL, playback.duration > 0 {
                levels.request(url: url, position: playback.position, duration: playback.duration)
            }
        }
    }

    private var requestKey: String {
        return "\(model.sourceURL?.path ?? "")-\(Int(playback.position / 2))-\(playback.duration)"
    }
}
