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
        for url in urls where url.pathExtension.lowercased() == "wav"
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
                job.state = .failed("ffmpeg не найден")
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
        // 1. Probe duration (suspends, does NOT block main thread)
        let duration = await probeDuration(url: job.inputURL, ffmpeg: ffmpeg)
        job.duration = duration
        job.state    = .converting

        // 2. Build arguments
        var args: [String] = ["-y", "-i", job.inputURL.path]
        args += preset.ditherMethod.ffmpegFilterArgs
        args += ["-codec:a", "libmp3lame", "-b:a", "\(preset.bitrate)k", job.outputURL.path]

        // 3. Launch process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError  = errPipe
        processes[job.id] = process

        // 4. Stream progress from stderr (fires on background thread)
        errPipe.fileHandleForReading.readabilityHandler = { [weak job] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text    = String(data: data, encoding: .utf8),
                  let elapsed = parseFFmpegTime(text),
                  let j       = job, j.duration > 0 else { return }
            let p = min(0.99, elapsed / j.duration)
            Task { @MainActor in j.progress = p }
        }

        // 5. Run
        do { try process.run() }
        catch {
            errPipe.fileHandleForReading.readabilityHandler = nil
            processes.removeValue(forKey: job.id)
            job.state = .failed(error.localizedDescription)
            return
        }

        // 6. Await termination (suspends, does NOT block main thread)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        // 7. Cleanup (back on main actor)
        errPipe.fileHandleForReading.readabilityHandler = nil
        processes.removeValue(forKey: job.id)

        if process.terminationStatus == 0 {
            job.progress = 1.0
            job.state    = .done
        } else if job.state != .cancelled {
            job.state = .failed("Exit \(process.terminationStatus)")
        }
    }

    // MARK: - Duration probe

    private func probeDuration(url: URL, ffmpeg: String) async -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-i", url.path]
        let pipe = Pipe()
        process.standardError  = pipe
        process.standardOutput = Pipe()
        guard (try? process.run()) != nil else { return 0 }

        return await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                cont.resume(returning: parseFFmpegDuration(text))
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
