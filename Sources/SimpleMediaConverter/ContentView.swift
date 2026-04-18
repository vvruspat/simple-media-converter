import SwiftUI

// MARK: - Root Layout

struct ContentView: View {
    @State private var queue   = ConversionQueue()
    @State private var store   = PresetStore()
    @State private var showSettings = false

    var body: some View {
        QueuePanel(queue: queue)
            .frame(minWidth: 500, minHeight: 420)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomBar(queue: queue, store: store, showSettings: $showSettings)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(store: store)
            }
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    let queue: ConversionQueue
    let store: PresetStore
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Overall progress bar
            ProgressView(value: queue.overallProgress)
                .progressViewStyle(.linear)
                .tint(overallTint)
                .animation(.linear(duration: 0.3), value: queue.overallProgress)

            HStack(alignment: .center, spacing: 10) {

                // Preset pill — click to edit
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                        Text(store.selected.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Редактировать пресет")

                // Status
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Convert / Cancel
                if queue.isRunning {
                    Text(String(format: "%.0f%%", queue.overallProgress * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Отмена") { queue.cancelAll() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                } else {
                    Button {
                        queue.startAll(preset: store.selected)
                    } label: {
                        Label("Конвертировать", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(queue.waitingCount == 0)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusLine: String {
        guard !queue.jobs.isEmpty else { return "" }
        let total = queue.jobs.count
        let done  = queue.doneCount
        if queue.isRunning { return "\(done)/\(total)" }
        if done == total   { return "✓ \(total) готово" }
        return "\(queue.waitingCount) в очереди"
    }

    private var overallTint: Color {
        if queue.overallProgress >= 1.0 { return .green }
        if queue.isRunning              { return .accentColor }
        return Color.secondary.opacity(0.4)
    }
}
