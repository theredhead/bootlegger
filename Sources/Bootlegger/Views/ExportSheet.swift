import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ProjectModel
    @State private var plan: ExportPlan
    @State private var fileSettings = FileExportSettings(defaults: .standard)
    @State private var showingFileOptions = false
    @AppStorage(ExportStrategy.preferenceKey) private var defaultStrategy = ExportStrategy.files.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var placeholder: ExportStrategy?
    @State private var validationError: String?

    init(model: ProjectModel) {
        self.model = model
        _plan = State(initialValue: ExportPlan(songs: model.project.songs))
    }

    private var strategy: ExportStrategy { return ExportStrategy(rawValue: defaultStrategy) ?? .files }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                .onMove { indices, destination in plan.songs.move(fromOffsets: indices, toOffset: destination)
                }
            }
            HStack {
                Button("Select All") { plan.selectedIDs = Set(plan.songs.map(\.id)) }
                Button("Deselect All") { plan.selectedIDs.removeAll() }
                Spacer()
                Text("\(plan.selectedSongs.count) tracks · \(ExportPlan.durationLabel(plan.duration))")
                    .monospacedDigit()
            }
            HStack {
                Button("File Options…") { showingFileOptions.toggle() }
                    .popover(isPresented: $showingFileOptions) {
                        FileExportOptions(
                            settings: $fileSettings, exampleProject: plan.project(from: model.project)
                        )
                        .padding(20).frame(width: 620)
                    }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Menu {
                    ForEach(ExportStrategy.allCases) { option in
                        Button(option.title) { perform(option) }
                    }
                } label: {
                    Text(strategy.title)
                } primaryAction: {
                    perform(strategy)
                }
                .help("Export using the default strategy, or choose another from the menu")
                .disabled(plan.selectedSongs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
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

    private func perform(_ strategy: ExportStrategy) {
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
        dismiss()
        // Let the sheet close before presenting the destination panel.
        let settings = fileSettings
        DispatchQueue.main.async { model.exportFiles(snapshot, settings: settings) }
    }
}
