import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ProjectModel
    @State private var plan: ExportPlan
    @State private var fileSettings = FileExportSettings(defaults: .standard)
    @State private var showingOptions = false
    @State private var netMDSettings = NetMDSettings(defaults: .standard)
    @ObservedObject private var netMD = NetMDController.shared
    @State private var strategy = ExportStrategy.files
    @Environment(\.dismiss) private var dismiss
    @State private var placeholder: ExportStrategy?
    @State private var validationError: String?
    @State private var activeExport: ExportStrategy?
    @State private var cancelling = false

    private var currentProgress: Double {
        return activeExport == .files ? model.exportProgress : netMD.progress
    }

    private var currentStatus: String {
        return activeExport == .files ? model.status : netMD.status
    }

    init(model: ProjectModel) {
        self.model = model
        _plan = State(initialValue: ExportPlan(songs: model.project.songs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if activeExport != nil {
                Spacer()
                ProgressView(value: currentProgress).frame(maxWidth: .infinity)
                Text(currentProgress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(maxWidth: .infinity)
                Text(currentStatus).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
                HStack {
                    Spacer()
                    Button(cancelling ? "Cancelling…" : "Cancel") {
                        cancelling = true
                        if activeExport == .files { model.cancelExport() } else { netMD.cancel() }
                    }
                    .disabled(cancelling)
                    .keyboardShortcut(.cancelAction)
                    .help(
                        activeExport == .miniDisc
                            ? "Finish the active track safely, then stop" : "Cancel export")
                }
            } else {
                Text("Export Album").font(.title2)
                Text("Choose tracks and drag them into export order.").foregroundStyle(.secondary)
                List {
                    ForEach(plan.songs) { song in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Toggle(
                                isOn: Binding(
                                    get: { plan.selectedIDs.contains(song.id) },
                                    set: { included in
                                        if included {
                                            plan.selectedIDs.insert(song.id)
                                        } else {
                                            plan.selectedIDs.remove(song.id)
                                        }
                                    })
                            ) {
                                Text(song.title).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            Text(ExportPlan.durationLabel(max(0, song.end - song.start))).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { indices, destination in
                        plan.songs.move(fromOffsets: indices, toOffset: destination)
                    }
                }
                HStack {
                    Button("Select All") { plan.selectedIDs = Set(plan.songs.map(\.id)) }
                    Button("Deselect All") { plan.selectedIDs.removeAll() }
                    Spacer()
                    Text("\(plan.selectedSongs.count) tracks · \(ExportPlan.durationLabel(plan.duration))")
                        .monospacedDigit()
                }
                if netMD.isWriting { ProgressView(value: netMD.progress) }
                if strategy == .miniDisc && (netMD.disc != nil || netMD.isWriting) {
                    Text(netMD.status).font(.caption)
                }
                HStack {
                    Spacer()
                    Button(netMD.isWriting ? "Stop After Track" : "Cancel") {
                        if netMD.isWriting { netMD.cancel() } else { dismiss() }
                    }.keyboardShortcut(.cancelAction)
                        .disabled(netMD.isBusy && !netMD.isWriting)
                    Button {
                        showingOptions.toggle()
                    } label: {
                        Label("Options", systemImage: "gearshape").labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Export Options")
                    .help("Options for \(strategy.title)")
                    .disabled(netMD.isBusy)
                    .popover(isPresented: $showingOptions) {
                        switch strategy {
                        case .files:
                            FileExportOptions(
                                settings: $fileSettings,
                                exampleProject: plan.project(from: model.project)
                            )
                            .padding(20).frame(width: 620)
                        case .miniDisc:
                            NetMDOptions(settings: $netMDSettings, songs: plan.selectedSongs)
                        case .compactDisc:
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CD Options").font(.title2)
                                Text(
                                    "CD writing is not implemented yet. Burner and disc options will appear here when supported."
                                )
                            }
                            .padding(20).frame(width: 360)
                        }
                    }
                    Menu {
                        ForEach(ExportStrategy.available(netMDAttached: netMD.hasAttachedDevice)) { option in
                            Button(option.title) { chooseStrategy(option) }
                        }
                    } label: {
                        Text(strategy.title)
                    } primaryAction: {
                        perform(strategy)
                    }
                    .help("Export using the selected strategy, or choose another from the menu")
                    .disabled(plan.selectedSongs.isEmpty || netMD.isBusy)
                }
            }
        }
        .padding(20)
        .frame(width: 660, height: activeExport == nil ? 540 : 240)
        .interactiveDismissDisabled(netMD.isBusy || activeExport != nil)
        .task {
            await netMD.detectDevices()
            strategy = ExportStrategy.preferred(netMDAttached: netMD.hasAttachedDevice)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                await netMD.detectDevices()
            }
        }
        .onChange(of: netMD.hasAttachedDevice) { _, attached in
            strategy = ExportStrategy.preferred(netMDAttached: attached)
            if !attached { showingOptions = false }
        }
        .onChange(of: fileSettings) { _, value in value.save(to: .standard) }
        .onChange(of: netMDSettings) { _, value in value.save(to: .standard) }
        .onChange(of: model.errorMessage) { _, message in
            if let message {
                validationError = message
                model.errorMessage = nil
            }
        }
        .onChange(of: netMD.errorMessage) { _, message in
            if let message {
                validationError = message
                netMD.errorMessage = nil
            }
        }
        .alert(
            "Cannot Export",
            isPresented: Binding(
                get: { validationError != nil }, set: { if !$0 { validationError = nil } }
            )
        ) {
            Button("OK") { validationError = nil }
        } message: {
            Text(validationError ?? "")
        }
        .alert(item: $placeholder) { strategy in
            Alert(
                title: Text(strategy.title), message: Text("This export strategy is not implemented yet."),
                dismissButton: .default(Text("OK")))
        }
    }

    private func chooseStrategy(_ selection: ExportStrategy) {
        guard ExportStrategy.available(netMDAttached: netMD.hasAttachedDevice).contains(selection) else {
            return
        }
        showingOptions = false
        strategy = selection
    }

    private func perform(_ strategy: ExportStrategy) {
        if strategy == .miniDisc {
            performNetMD()
            return
        }
        guard strategy == .files else {
            placeholder = strategy
            return
        }
        let snapshot = plan.project(from: model.project)
        do {
            try AudioExporter.validate(project: snapshot, duration: model.playback.duration)
            _ = try fileSettings.filenames(project: snapshot)
        } catch {
            validationError = error.localizedDescription
            return
        }
        cancelling = false
        let started = model.exportFiles(snapshot, settings: fileSettings) { succeeded in
            if succeeded {
                dismiss()
            } else {
                activeExport = nil
                cancelling = false
            }
        }
        if started { activeExport = .files }
    }

    private func performNetMD() {
        guard netMD.hasAttachedDevice else {
            strategy = .files
            return
        }
        guard let disc = netMD.disc else {
            showingOptions = true
            return
        }
        let snapshot = plan.project(from: model.project)
        do {
            try AudioExporter.validate(project: snapshot, duration: model.playback.duration)
            try NetMDPreflight.validate(songs: snapshot.songs, disc: disc, settings: netMDSettings)
            guard let source = model.sourceURL else { return }
            let settings = netMDSettings
            cancelling = false
            activeExport = .miniDisc
            Task {
                let succeeded = await netMD.write(
                    project: snapshot, sourceURL: source, settings: settings, confirmedDisc: disc)
                if succeeded {
                    dismiss()
                } else {
                    activeExport = nil
                    cancelling = false
                }
            }
        } catch {
            validationError = error.localizedDescription
            showingOptions = true
        }
    }
}
