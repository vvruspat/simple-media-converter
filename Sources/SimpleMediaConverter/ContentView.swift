import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var converter = ConversionManager()
    @AppStorage("lastBitrate") private var selectedBitrate = 320
    @State private var droppedFile: URL?
    @State private var isTargeted = false

    private let bitrates = [128, 256, 320]

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            HStack {
                Text("Bitrate")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Bitrate", selection: $selectedBitrate) {
                    ForEach(bitrates, id: \.self) { br in
                        Text("\(br) kbps").tag(br)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .labelsHidden()
            }

            Button {
                startConversion()
            } label: {
                HStack(spacing: 8) {
                    if converter.isConverting {
                        ProgressView().controlSize(.small)
                    }
                    Text(converter.isConverting ? "Конвертирую…" : "Convert to MP3")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(droppedFile == nil || converter.isConverting)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(converter.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var statusColor: Color {
        if converter.isConverting { return .orange }
        if converter.status.hasPrefix("✓") { return .green }
        if converter.status.hasPrefix("Ошибка") || converter.status.hasPrefix("ffmpeg") { return .red }
        return Color.secondary.opacity(0.5)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.07)
                              : Color.secondary.opacity(0.04))
                )

            VStack(spacing: 10) {
                Image(systemName: droppedFile != nil ? "waveform" : "square.and.arrow.down")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(droppedFile != nil ? Color.accentColor : Color.secondary)

                if let file = droppedFile {
                    Text(file.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 16)
                    Text("Tap to change")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Drop WAV file here")
                        .font(.headline)
                    Text("16 / 24 / 32-bit · or click to browse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 148)
        .contentShape(Rectangle())
        .onTapGesture { openFilePicker() }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .animation(.easeInOut(duration: 0.2), value: droppedFile?.path)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil),
                url.pathExtension.lowercased() == "wav"
            else { return }
            DispatchQueue.main.async {
                droppedFile = url
                converter.status = "Ready — \(url.lastPathComponent)"
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a WAV file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        droppedFile = url
        converter.status = "Ready — \(url.lastPathComponent)"
    }

    private func startConversion() {
        guard let input = droppedFile else { return }

        let panel = NSSavePanel()
        panel.title = "Save MP3 file"
        panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent
        panel.directoryURL = input.deletingLastPathComponent()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let output = panel.url else { return }
        converter.convert(input: input, output: output, bitrate: selectedBitrate)
    }
}
