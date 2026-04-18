import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Queue Panel

struct QueuePanel: View {
    let queue: ConversionQueue
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if queue.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .frame(minWidth: 340)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(dropHighlight)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .toolbar { toolbarContent }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Drop media files here")
                .font(.headline)
            Text("Audio & video · any format ffmpeg supports")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: Job list

    private var jobList: some View {
        List {
            ForEach(queue.jobs) { job in
                JobRow(job: job) { queue.remove(job: job) }
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
        .listStyle(.plain)
        .animation(.default, value: queue.jobs.map(\.id))
    }

    // MARK: Drop highlight

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(3)
            .opacity(isTargeted ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { addFilesViaPicker() } label: {
                Label("Add Files", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button("Clear Done") { queue.clearDone() }
                .disabled(queue.doneCount == 0)
        }
        ToolbarItem {
            Button("Reset") { queue.resetWaiting() }
                .disabled(queue.jobs.filter { $0.state.isTerminal }.isEmpty)
                .help("Reset completed/failed jobs back to waiting")
        }
    }

    // MARK: Handlers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url  = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { queue.add(urls: urls) }
        return true
    }

    private func addFilesViaPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes    = [.audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles          = true
        panel.title = "Choose media files"
        guard panel.runModal() == .OK else { return }
        queue.add(urls: panel.urls)
    }
}

// MARK: - Job Row

struct JobRow: View {
    let job: ConversionJob
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            stateIcon.frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(.body, design: .default))

                if job.state == .converting {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(progressTint)
                        .animation(.linear(duration: 0.3), value: job.progress)
                } else {
                    Text(job.statusLabel)
                        .font(.caption)
                        .foregroundStyle(labelStyle)
                }
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .opacity((isHovered || job.state.isTerminal) ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var progressTint: Color {
        job.progress > 0.98 ? .green : .accentColor
    }

    private var labelStyle: Color {
        switch job.state {
        case .done:   .green
        case .failed: .red
        default:      .secondary
        }
    }
}
