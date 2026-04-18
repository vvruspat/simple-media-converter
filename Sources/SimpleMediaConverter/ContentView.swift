import SwiftUI

// MARK: - Root Layout

struct ContentView: View {
    @State private var queue = ConversionQueue()
    @State private var store = PresetStore()

    var body: some View {
        HSplitView {
            QueuePanel(queue: queue)
            SettingsPanel(store: store)
        }
        .frame(minWidth: 660, minHeight: 440)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(queue: queue, store: store)
        }
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    let queue: ConversionQueue
    let store: PresetStore

    var body: some View {
        VStack(spacing: 6) {
            // Overall progress
            ProgressView(value: queue.overallProgress)
                .progressViewStyle(.linear)
                .tint(overallTint)
                .animation(.linear(duration: 0.3), value: queue.overallProgress)

            HStack(alignment: .center, spacing: 12) {
                // Status text
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    if queue.isRunning {
                        Text(String(format: "%.0f%% общий прогресс  •  %d активных",
                                    queue.overallProgress * 100, queue.activeCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Buttons
                if queue.isRunning {
                    Button("Отмена") { queue.cancelAll() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                } else {
                    Button {
                        queue.startAll(preset: store.selected)
                    } label: {
                        Label("Конвертировать", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queue.waitingCount == 0)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusLine: String {
        guard !queue.jobs.isEmpty else { return "Добавьте файлы в очередь" }
        let total = queue.jobs.count
        let done  = queue.doneCount
        let wait  = queue.waitingCount
        if queue.isRunning {
            return "\(done) из \(total) файлов готово"
        }
        if done == total {
            return "✓ Все \(total) файлов сконвертированы"
        }
        return "\(total) файлов  •  \(wait) в очереди  •  \(done) готово"
    }

    private var overallTint: Color {
        if queue.overallProgress >= 1.0 { return .green }
        if queue.isRunning              { return .accentColor }
        return .secondary
    }
}
