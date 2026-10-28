import SwiftUI

struct NetMDSettingsView: View {
    @Binding var settings: NetMDSettings
    var disc: NetMDDisc?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Recording mode", selection: $settings.mode) {
                ForEach(NetMDMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                        .disabled(
                            disc == nil
                                || (mode != .sp && disc?.supportsLPEncoding != true
                                    && disc?.supportsSoftwareLP != true)
                        )
                }
            }
            Picker("Encode with", selection: $settings.encoding) {
                ForEach(NetMDEncoding.allCases) { encoding in
                    Text(encoding.title).tag(encoding)
                        .disabled(!supports(encoding))
                }
            }
            Toggle("Use gapless SP on compatible recorders with an empty disc", isOn: $settings.gaplessSP)
                .disabled(settings.encoding != .recorder || disc?.supportsGaplessSP != true)
            Text(
                settings.encoding == .software
                    ? "Software ATRAC sends less data over USB and may transfer faster. LP2/LP4 trade audio quality for longer playing time. Software SP is available only on supported recorders; its sound may differ from the recorder’s encoder."
                    : "Recorder SP uses the device’s ATRAC encoder. On-device LP encoding is offered only where supported."
            )
            .font(.caption).foregroundStyle(.secondary)
            if settings.encoding == .software && settings.mode == .lp4 {
                Text(
                    "Software LP4 is experimental. Verify playback and track endings before exporting a full concert."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { reconcileEncoding() }
        .onChange(of: settings.mode) { _, _ in reconcileEncoding() }
        .onChange(of: disc) { _, _ in reconcileEncoding() }
    }

    private func supports(_ encoding: NetMDEncoding) -> Bool {
        guard let disc else { return false }
        if encoding == .software {
            return settings.mode == .sp ? disc.supportsSoftwareSP : disc.supportsSoftwareLP
        }
        return settings.mode == .sp || disc.supportsLPEncoding
    }

    private func reconcileEncoding() {
        guard disc != nil, !supports(settings.encoding) else { return }
        if supports(.recorder) {
            settings.encoding = .recorder
        } else if supports(.software) {
            settings.encoding = .software
        }
    }
}

struct NetMDOptions: View {
    @Binding var settings: NetMDSettings
    var songs: [Song]
    @ObservedObject private var controller = NetMDController.shared
    @State private var eraseCandidate: NetMDDisc?
    @State private var confirmingErase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MiniDisc").font(.title2)
                Spacer()
                Button("Refresh") { Task { await controller.refresh() } }.disabled(controller.isBusy)
            }
            NetMDSettingsView(settings: $settings, disc: controller.disc).disabled(controller.isBusy)
            Divider()
            if let disc = controller.disc {
                Text(disc.device).font(.headline)
                Text(disc.title.isEmpty ? "Untitled MD" : disc.title)
                Text(
                    "\(disc.trackCount) existing tracks · \(ExportPlan.durationLabel(disc.availableSeconds * settings.mode.capacityFactor)) available in \(settings.mode.title)"
                )
                .monospacedDigit()
                if !disc.writable { Text("Disc is write-protected or not recordable.").foregroundStyle(.red) }
                let gapless = NetMDPreflight.usesGapless(disc: disc, settings: settings)
                Text(
                    gapless
                        ? "Gapless SP transfer is available for this empty disc."
                        : "Tracks will be transferred individually."
                )
                .font(.caption)
                if let reason = preflightError(disc) {
                    Text(reason).foregroundStyle(.red).font(.caption)
                }
                Button("Erase / Format Disc…", role: .destructive) {
                    eraseCandidate = disc
                    confirmingErase = true
                }
                .disabled(controller.isBusy || !disc.writable)
                Text(
                    "Erasing removes every track and restores free capacity in standard MD mode. Hi-MD formatting is not supported."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Text(controller.status).font(.callout)
            if controller.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(20).frame(width: 520)
        .task { if controller.disc == nil { await controller.refresh() } }
        .alert("Erase all tracks from this MiniDisc?", isPresented: $confirmingErase) {
            Button("Cancel", role: .cancel) { eraseCandidate = nil }
            Button("Erase Disc", role: .destructive) {
                if let confirmed = eraseCandidate { Task { await controller.erase(confirmed) } }
                eraseCandidate = nil
            }
        } message: {
            if let disc = eraseCandidate {
                Text(
                    "\(disc.device) — \(disc.title.isEmpty ? "Untitled MD" : disc.title)\nAll \(disc.trackCount) tracks will be permanently deleted. This cannot be undone."
                )
            }
        }
    }

    private func preflightError(_ disc: NetMDDisc) -> String? {
        guard !songs.isEmpty else { return nil }
        do {
            try NetMDPreflight.validate(songs: songs, disc: disc, settings: settings)
            return nil
        } catch { return error.localizedDescription }
    }
}
