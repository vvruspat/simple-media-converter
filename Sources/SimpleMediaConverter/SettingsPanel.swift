import SwiftUI
import AppKit

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Bindable var store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNewSheet  = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack {
                Text("Preset")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // ── Preset picker + actions ──────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $store.selectedID) {
                    ForEach(store.presets) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                .onChange(of: store.selectedID) { _, _ in store.save() }

                HStack(spacing: 8) {
                    Button {
                        var blank = ConversionPreset.default
                        blank.id   = UUID()
                        blank.name = "New Preset"
                        store.presets.append(blank)
                        store.selectedID = blank.id
                        store.save()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        newPresetName = store.selected.name + " Copy"
                        showNewSheet  = true
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        store.deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.presets.count <= 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // ── Settings form ────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    formField("Name") {
                        TextField("Preset name", text: bind(\.name))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { store.save() }
                    }

                    // ── Output format ────────────────────────────────────
                    formField("Output format") {
                        Picker("", selection: bind(\.outputFormat)) {
                            Section("Audio") {
                                ForEach(OutputFormat.audioFormats) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                            Section("Video") {
                                ForEach(OutputFormat.videoFormats) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                        }
                        .labelsHidden()
                        .onChange(of: store.selected.outputFormat) { _, _ in store.save() }
                    }

                    // ── Audio bitrate (lossy audio / video with audio) ───
                    if !store.selected.outputFormat.isLossless
                        && store.selected.outputFormat.supportsAudio {
                        formField("Audio bitrate") {
                            Picker("", selection: bind(\.bitrate)) {
                                Text("64 kbps").tag(64)
                                Text("96 kbps").tag(96)
                                Text("128 kbps").tag(128)
                                Text("192 kbps").tag(192)
                                Text("256 kbps").tag(256)
                                Text("320 kbps").tag(320)
                            }
                            .labelsHidden()
                            .onChange(of: store.selected.bitrate) { _, _ in store.save() }
                        }
                    }

                    // ── Dither (audio-only lossy formats) ───────────────
                    if !store.selected.outputFormat.isVideo
                        && !store.selected.outputFormat.isLossless {
                        formField("Dither") {
                            Picker("", selection: bind(\.ditherMethod)) {
                                ForEach(DitherMethod.allCases) { m in
                                    Text(m.displayName).tag(m)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: store.selected.ditherMethod) { _, _ in store.save() }
                        }
                    }

                    // ── Video quality / CRF (video formats except GIF) ──
                    if store.selected.outputFormat.isVideo
                        && store.selected.outputFormat != .gif {
                        formField("Video quality (CRF)") {
                            HStack(spacing: 0) {
                                Picker("", selection: bind(\.videoCRF)) {
                                    Text("High").tag(18)
                                    Text("Medium").tag(23)
                                    Text("Small file").tag(28)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .onChange(of: store.selected.videoCRF) { _, _ in store.save() }
                                Text("CRF \(store.selected.videoCRF)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                        }
                    }

                    // ── Output folder ────────────────────────────────────
                    formField("Output folder") {
                        HStack(spacing: 8) {
                            Text(outputFolderLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose…") { pickOutputFolder() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            if store.selected.outputFolderPath != nil {
                                Button { clearOutputFolder() } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // ── Filename template ────────────────────────────────
                    formField("Filename template") {
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("{name}", text: bind(\.filenameTemplate))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .onSubmit { store.save() }

                            Text("{name}  {bitrate}  {format}  {dither}  {date}")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            Text("→ \(store.selected.previewFilename())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 360)
        .fixedSize(horizontal: true, vertical: false)
        .sheet(isPresented: $showNewSheet) {
            duplicateSheet
        }
    }

    // MARK: - Duplicate name sheet

    private var duplicateSheet: some View {
        VStack(spacing: 20) {
            Text("Duplicate Preset")
                .font(.headline)
            TextField("Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { confirmDuplicate() }
            HStack {
                Button("Cancel") { showNewSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { confirmDuplicate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 280)
    }

    private func confirmDuplicate() {
        var copy  = store.selected
        copy.id   = UUID()
        copy.name = newPresetName.trimmingCharacters(in: .whitespaces)
        store.presets.append(copy)
        store.selectedID = copy.id
        store.save()
        showNewSheet = false
    }

    // MARK: - Helpers

    private func bind<T>(_ kp: WritableKeyPath<ConversionPreset, T>) -> Binding<T> {
        Binding(
            get: { store.selected[keyPath: kp] },
            set: {
                var p = store.selected
                p[keyPath: kp] = $0
                store.selected = p
            }
        )
    }

    private var outputFolderLabel: String {
        store.selected.outputFolderPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? "Same as source"
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Choose Output Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var p = store.selected; p.outputFolder = url; store.selected = p
    }

    private func clearOutputFolder() {
        var p = store.selected; p.outputFolderPath = nil; store.selected = p
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
