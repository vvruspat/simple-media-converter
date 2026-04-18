import Foundation
import AppKit

@MainActor
@Observable
final class ConversionQueue {

    // MARK: - State

    var jobs: [ConversionJob] = []
    var isRunning = false

    private var conversionTask: Task<Void, Never>?
    private var processes: [UUID: Process] = [:]

    // MARK: - Supported input extensions

    private static let supportedExtensions: Set<String> = [
        // Audio
        "mp3", "aac", "m4a", "flac", "wav", "aiff", "aif", "ogg", "opus", "wma", "alac",
        // Video
        "mp4", "mkv", "mov", "webm", "avi", "m4v", "wmv", "flv", "ts", "mts", "m2ts",
        "3gp", "ogv", "mpg", "mpeg", "vob", "f4v", "divx", "rm", "rmvb"
    ]

    // MARK: - FFmpeg

    var ffmpegPath: String? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Derived

    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        return jobs.map(\.progress).reduce(0, +) / Double(jobs.count)
    }
    var doneCount:    Int { jobs.filter { $0.state == .done }.count }
    var waitingCount: Int { jobs.filter { $0.state == .waiting }.count }
    var activeCount:  Int { jobs.filter { $0.state == .converting }.count }

    // MARK: - Queue management

    func add(urls: [URL]) {
        let existing = Set(jobs.map { $0.inputURL.standardizedFileURL })
        for url in urls
            where Self.supportedExtensions.contains(url.pathExtension.lowercased())
               && !existing.contains(url.standardizedFileURL) {
            jobs.append(ConversionJob(inputURL: url, outputURL: url))
        }
    }

    func remove(job: ConversionJob) {
        if job.state == .converting { processes[job.id]?.terminate() }
        jobs.removeAll { $0.id == job.id }
    }

    func clearDone() {
        jobs.removeAll { $0.state.isTerminal }
    }

    func resetWaiting() {
        for job in jobs where job.state.isTerminal {
            job.state    = .waiting
            job.progress = 0
        }
    }

    // MARK: - Start / Cancel

    func startAll(preset: ConversionPreset) {
        guard let ffmpeg = ffmpegPath else {
            for job in jobs where job.state == .waiting {
                job.state = .failed("ffmpeg not found")
            }
            return
        }
        let pending = jobs.filter { $0.state == .waiting }
        guard !pending.isEmpty else { return }

        for job in pending { job.outputURL = preset.outputURL(for: job.inputURL) }

        isRunning = true
        let concurrency = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)

        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var remaining = ArraySlice(pending)
                var active    = 0

                while active < concurrency, let job = remaining.popFirst() {
                    group.addTask { @MainActor in await self.runJob(job, ffmpeg: ffmpeg, preset: preset) }
                    active += 1
                }
                for await _ in group {
                    active -= 1
                    if let job = remaining.popFirst() {
                        group.addTask { @MainActor in await self.runJob(job, ffmpeg: ffmpeg, preset: preset) }
                        active += 1
                    }
                }
            }
            let doneURLs = self.jobs.filter { $0.state == .done }.map(\.outputURL)
            if !doneURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(doneURLs)
            }
            self.isRunning = false
        }
    }

    func cancelAll() {
        conversionTask?.cancel()
        for (_, p) in processes { p.terminate() }
        processes.removeAll()
        for job in jobs where job.state == .converting {
            job.state    = .cancelled
            job.progress = 0
        }
        isRunning = false
    }

    // MARK: - Single-job runner

    private func runJob(_ job: ConversionJob,
                        ffmpeg: String,
                        preset: ConversionPreset) async {
        // 1. Probe duration + stream info
        print("[runJob] probing \(job.inputURL.lastPathComponent)")
        let (duration, hasVideo) = await probeMedia(url: job.inputURL, ffmpeg: ffmpeg)
        print("[runJob] probe done: duration=\(duration) hasVideo=\(hasVideo)")
        job.duration = duration

        // 2. Guard: GIF requires video input
        if preset.outputFormat == .gif && !hasVideo {
            job.state = .failed("GIF requires a video source")
            return
        }

        job.state = .converting

        // 3. Build arguments via preset
        let args = preset.ffmpegArgs(
            inputPath:     job.inputURL.path,
            outputPath:    job.outputURL.path,
            hasVideoInput: hasVideo
        )
        print("[runJob] args: \(args.joined(separator: " "))")

        // 4. Launch process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args

        let errPipe = Pipe()
        process.standardInput  = FileHandle.nullDevice  // prevent ffmpeg waiting on stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = errPipe
        processes[job.id] = process

        // 5. Stream progress from stderr (fires on background thread)
        errPipe.fileHandleForReading.readabilityHandler = { [weak job] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text    = String(data: data, encoding: .utf8),
                  let elapsed = parseFFmpegTime(text),
                  let j       = job, j.duration > 0 else { return }
            let p = min(0.99, elapsed / j.duration)
            Task { @MainActor in j.progress = p }
        }

        // 6. Run
        print("[runJob] launching ffmpeg…")
        do { try process.run() }
        catch {
            errPipe.fileHandleForReading.readabilityHandler = nil
            processes.removeValue(forKey: job.id)
            job.state = .failed(error.localizedDescription)
            print("[runJob] launch error: \(error)")
            return
        }
        print("[runJob] ffmpeg launched pid=\(process.processIdentifier), waiting…")

        // 7. Await termination
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { p in
                print("[runJob] ffmpeg exited status=\(p.terminationStatus)")
                cont.resume()
            }
        }

        // 8. Cleanup
        errPipe.fileHandleForReading.readabilityHandler = nil
        processes.removeValue(forKey: job.id)

        if process.terminationStatus == 0 {
            job.progress = 1.0
            job.state    = .done
        } else if job.state != .cancelled {
            job.state = .failed("Exit \(process.terminationStatus)")
        }
    }

    // MARK: - Media probe (duration + stream info)
    //
    // Intentionally avoids Pipe() — concurrent processes inherit each other's
    // pipe write-ends, causing readDataToEndOfFile() to block forever.
    // Temp-file redirect sidesteps all pipe-inheritance issues.

    private func probeMedia(url: URL, ffmpeg: String) async -> (duration: Double, hasVideo: Bool) {
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let tmpPath = NSTemporaryDirectory() + "probe_\(UUID().uuidString).txt"
                defer { try? FileManager.default.removeItem(atPath: tmpPath) }

                FileManager.default.createFile(atPath: tmpPath, contents: nil)
                guard let writeHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: tmpPath)) else {
                    cont.resume(returning: (0, false)); return
                }

                let process = Process()
                process.executableURL  = URL(fileURLWithPath: ffmpeg)
                process.arguments      = ["-i", url.path]
                process.standardInput  = FileHandle.nullDevice  // prevent ffmpeg waiting on stdin
                process.standardOutput = writeHandle
                process.standardError  = writeHandle

                guard (try? process.run()) != nil else {
                    writeHandle.closeFile()
                    cont.resume(returning: (0, false)); return
                }

                process.waitUntilExit()
                writeHandle.closeFile()

                let text     = (try? String(contentsOfFile: tmpPath)) ?? ""
                let duration = parseFFmpegDuration(text)
                let hasVideo = text.contains("Video:")
                print("[probe] \(url.lastPathComponent) → duration=\(duration) hasVideo=\(hasVideo)")
                cont.resume(returning: (duration, hasVideo))
            }
        }
    }
}

// MARK: - Parsing helpers (module-level, thread-safe)

private func parseFFmpegTime(_ text: String) -> Double? {
    guard let r = text.range(of: #"time=(\d{2}):(\d{2}):(\d{2}\.\d+)"#,
                             options: .regularExpression) else { return nil }
    return parseHMS(String(text[r]).dropFirst(5))
}

private func parseFFmpegDuration(_ text: String) -> Double {
    guard let r = text.range(of: #"Duration: (\d{2}):(\d{2}):(\d{2}\.\d+)"#,
                             options: .regularExpression) else { return 0 }
    return parseHMS(String(text[r]).dropFirst("Duration: ".count)) ?? 0
}

private func parseHMS<S: StringProtocol>(_ s: S) -> Double? {
    let parts = s.components(separatedBy: ":")
    guard parts.count == 3,
          let h   = Double(parts[0]),
          let m   = Double(parts[1]),
          let sec = Double(parts[2]) else { return nil }
    return h * 3600 + m * 60 + sec
}
