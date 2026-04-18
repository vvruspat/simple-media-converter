import Foundation

// MARK: - Job State

enum JobState: Equatable {
    case waiting
    case converting
    case done
    case failed(String)
    case cancelled

    var isTerminal: Bool {
        switch self { case .done, .failed, .cancelled: true; default: false }
    }

    var systemImage: String {
        switch self {
        case .waiting:    "clock"
        case .converting: "arrow.2.circlepath"
        case .done:       "checkmark.circle.fill"
        case .failed:     "exclamationmark.circle.fill"
        case .cancelled:  "minus.circle.fill"
        }
    }
}

// MARK: - Conversion Job

@Observable
final class ConversionJob: Identifiable {
    let id       = UUID()
    let inputURL: URL
    var outputURL: URL
    var state: JobState = .waiting
    var progress: Double = 0.0   // 0…1
    var duration: Double = 0.0   // seconds (from ffmpeg probe)

    var displayName: String { inputURL.lastPathComponent }

    var statusLabel: String {
        switch state {
        case .waiting:        "В очереди"
        case .converting:     String(format: "%.0f%%", progress * 100)
        case .done:           "✓ \(outputURL.lastPathComponent)"
        case .failed(let m):  "Ошибка: \(m)"
        case .cancelled:      "Отменено"
        }
    }

    init(inputURL: URL, outputURL: URL) {
        self.inputURL  = inputURL
        self.outputURL = outputURL
    }
}
