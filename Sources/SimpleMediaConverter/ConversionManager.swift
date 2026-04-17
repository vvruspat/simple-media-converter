import Foundation
import AppKit
import Observation

@Observable
final class ConversionManager {
    var isConverting = false
    var status = "Ready"

    private var ffmpegPath: String? {
        // Prefer bundled binary (inside .app/Contents/MacOS/)
        if let url = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        // Dev fallback: system-installed
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func convert(input: URL, output: URL, bitrate: Int) {
        guard let ffmpeg = ffmpegPath else {
            status = "ffmpeg не найден"
            return
        }

        isConverting = true
        status = "Конвертирую…"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-i", input.path,
            "-af", "aresample=dither_method=triangular_hp",
            "-codec:a", "libmp3lame",
            "-b:a", "\(bitrate)k",
            output.path
        ]

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isConverting = false
                if proc.terminationStatus == 0 {
                    self.status = "✓ Сохранено: \(output.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    self.status = "Ошибка (код \(proc.terminationStatus))"
                    print("[ffmpeg stderr]\n\(msg)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            isConverting = false
            status = "Не удалось запустить ffmpeg: \(error.localizedDescription)"
        }
    }
}
