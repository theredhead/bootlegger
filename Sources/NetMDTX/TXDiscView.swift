import SwiftUI

struct TXDiscView: View {
    @ObservedObject var library: TXLibrary
    @ObservedObject private var controller = NetMDController.shared
    @ObservedObject private var extraction: TXExtraction

    init(library: TXLibrary) {
        self.library = library
        extraction = library.extraction
    }

    private var transferActive: Bool {
        return library.isImporting || library.isTransferring || extraction.isActive
    }

    private var totalCount: Int { return extraction.isActive ? extraction.totalCount : library.totalCount }
    private var currentNumber: Int {
        return extraction.isActive ? extraction.currentNumber : min(library.completedCount + 1, totalCount)
    }
    private var overallProgress: Double {
        return extraction.isActive
            ? extraction.overallProgress(trackProgress: controller.progress)
            : library.overallProgress(trackProgress: controller.progress)
    }

    var body: some View {
        TXTrackTable(library: library, extraction: extraction)
            .frame(minWidth: 580, minHeight: 320)
            .sheet(isPresented: Binding(get: { transferActive }, set: { _ in })) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(extraction.isActive ? "Copying to Mac" : "Copying to MiniDisc").font(.title2)
                    if totalCount > 0 {
                        Text("Working on \(currentNumber) of \(totalCount)").font(.headline)
                        Text(extraction.isActive ? extraction.currentFilename : library.currentFilename)
                            .lineLimit(1)
                        ProgressView(value: overallProgress)
                        Text(overallProgress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    } else {
                        ProgressView()
                        Text("Preparing dropped recordings…")
                    }
                    Text(extraction.isActive ? extraction.status : controller.status)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Stop After Track") {
                            if extraction.isActive { extraction.cancel() } else { library.cancel() }
                        }
                        .disabled(extraction.isActive ? extraction.cancelling : !library.isTransferring)
                    }
                }
                .padding(24).frame(width: 440)
                .interactiveDismissDisabled()
            }
            .onChange(of: extraction.error) { _, message in
                if let message {
                    library.error = message
                    extraction.error = nil
                }
            }
            .alert(
                "Cannot Transfer",
                isPresented: Binding(
                    get: { library.error != nil && !transferActive }, set: { if !$0 { library.error = nil } }
                )
            ) {
                Button("OK") { library.error = nil }
                if !library.queue.isEmpty {
                    Button("Retry Pending Copies") {
                        Task { await library.transfer(settings: library.settings) }
                    }
                    Button("Discard Pending Copies") {
                        for item in library.queue { library.remove(item.id) }
                    }
                }
            } message: {
                Text(library.error ?? "")
            }
    }
}

struct TXSettingsView: View {
    @ObservedObject var library: TXLibrary
    @ObservedObject private var controller = NetMDController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copy to Mac").font(.headline)
            Toggle("Convert extracted SP audio to WAV", isOn: $library.convertToWAV)
            Text(
                "Otherwise preserve original ATRAC audio as an AEA file. Extraction currently supports RH1 SP tracks."
            )
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Copy to MiniDisc").font(.headline)
            NetMDSettingsView(settings: $library.settings, disc: controller.disc)
            Text("Dropped files are copied as separate tracks.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 500)
    }
}
