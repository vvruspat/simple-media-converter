import SwiftUI
import AppKit

// MARK: - Settings Panel (right side)

struct SettingsPanel: View {
    @Bindable var store: PresetStore
    @State private var showNewPresetSheet = false
    @State private var newPresetName = ""

    private var preset: ConversionPreset {
        get { store.selected }
        nonmutating set { store.selected = newValue }
    }

    // Helper: binding to any ConversionPreset property
    private func bind<T>(_ kp: WritableKeyPath<ConversionPreset, T>) -> Binding<T> {
        Binding(
            get: { self.store.selected[keyPath: kp] },
            set: {
                var p = self.store.selected
                p[keyPath: kp] = $0
                self.store.selected = p
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                presetSelector
                Divider()
                settingsForm
            }
        }
        .frame(width: 268)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showNewPresetSheet) {
            newPresetSheet
        }
    }

    // MARK: Preset Selector

    private var presetSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESET")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Picker("", selection: $store.selectedID) {
                ForEach(store.presets) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .labelsHidden()
            .padding(.horizontal, 12)
            .onChange(of: store.selectedID) { _, _ in store.save() }

            HStack(spacing: 6) {
                Button {
                    newPresetName = store.selected.name + " Copy"
                    showNewPresetSheet = true
                } label: {
                    Label("Duplicate", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    store.deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.presets.count <= 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: Settings Form

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Preset name
            settingRow(label: "Name") {
                TextField("Preset name", text: bind(\.name))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.save() }
            }

            // Bitrate
            settingRow(label: "Bitrate") {
                Picker("", selection: bind(\.bitrate)) {
                    Text("128 kbps").tag(128)
                    Text("256 kbps").tag(256)
                    Text("320 kbps").tag(320)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: store.selected.bitrate) { _, _ in store.save() }
            }

            // Dither
            settingRow(label: "Dither") {
                Picker("", selection: bind(\.ditherMethod)) {
                    ForEach(DitherMethod.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .onChange(of: store.selected.ditherMethod) { _, _ in store.save() }
            }

            // Output folder
            settingRow(label: "Output") {
                HStack(spacing: 6) {
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
                        Button("✕") {
                            var p = store.selected
                            p.outputFolderPath = nil
                            store.selected = p
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Filename template
            settingRow(label: "Template") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("{name}", text: bind(\.filenameTemplate))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { store.save() }

                    Text("Tokens: {name} {bitrate} {dither} {date}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("→ " + store.selected.previewFilename())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 20)
        }
        .padding(16)
    }

    // MARK: Helpers

    @ViewBuilder
    private func settingRow<Content: View>(label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var outputFolderLabel: String {
        if let path = store.selected.outputFolderPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Same as source"
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Choose Output Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var p = store.selected
        p.outputFolder = url
        store.selected = p
    }

    // MARK: New Preset Sheet

    private var newPresetSheet: some View {
        VStack(spacing: 20) {
            Text("Duplicate Preset")
                .font(.headline)

            TextField("Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { createPreset() }

            HStack {
                Button("Cancel") { showNewPresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createPreset() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func createPreset() {
        var copy = store.selected
        copy.id   = UUID()
        copy.name = newPresetName.trimmingCharacters(in: .whitespaces)
        store.presets.append(copy)
        store.selectedID = copy.id
        store.save()
        showNewPresetSheet = false
    }
}
