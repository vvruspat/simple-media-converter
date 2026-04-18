import Foundation
import AppKit

// MARK: - Output Format

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    // Audio
    case mp3, aac, m4a, flac, wav, aiff, ogg, opus
    // Video
    case mp4, mkv, mov, webm, avi, gif

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var displayName: String { rawValue.uppercased() }

    var isVideo: Bool {
        switch self {
        case .mp4, .mkv, .mov, .webm, .avi, .gif: true
        default: false
        }
    }

    var isLossless: Bool {
        switch self {
        case .flac, .wav, .aiff: true
        default: false
        }
    }

    var supportsAudio: Bool { self != .gif }

    var audioCodecArgs: [String] {
        switch self {
        case .mp3:                              return ["-codec:a", "libmp3lame"]
        case .aac, .m4a, .mp4, .mkv, .mov, .avi: return ["-codec:a", "aac"]
        case .flac:                             return ["-codec:a", "flac"]
        case .wav:                              return ["-codec:a", "pcm_s16le"]
        case .aiff:                             return ["-codec:a", "pcm_s16be"]
        case .ogg:                              return ["-codec:a", "libvorbis"]
        case .opus, .webm:                      return ["-codec:a", "libopus"]
        case .gif:                              return []
        }
    }

    var videoCodecArgs: [String] {
        switch self {
        case .mp4, .mkv, .mov, .avi: return ["-codec:v", "libx264", "-pix_fmt", "yuv420p"]
        case .webm:                  return ["-codec:v", "libvpx-vp9"]
        default:                     return []
        }
    }

    static var audioFormats: [OutputFormat] { allCases.filter { !$0.isVideo } }
    static var videoFormats: [OutputFormat] { allCases.filter { $0.isVideo } }
}

// MARK: - Dither Method

enum DitherMethod: String, CaseIterable, Codable, Identifiable {
    case none              = "none"
    case rectangular       = "rectangular"
    case triangular        = "triangular"
    case triangularHP      = "triangular_hp"
    case lipshitz          = "lipshitz"
    case shibata           = "shibata"
    case fWeighted         = "f_weighted"
    case modifiedEWeighted = "modified_e_weighted"
    case improvedEWeighted = "improved_e_weighted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:              "None"
        case .rectangular:       "Rectangular (RPDF)"
        case .triangular:        "Triangular (TPDF)"
        case .triangularHP:      "Triangular HP"
        case .lipshitz:          "Lipshitz"
        case .shibata:           "Shibata ★"
        case .fWeighted:         "F-Weighted"
        case .modifiedEWeighted: "Modified E-Weighted"
        case .improvedEWeighted: "Improved E-Weighted"
        }
    }

    var ffmpegFilterArgs: [String] {
        if self == .none { return [] }
        return ["-af", "aresample=dither_method=\(rawValue),aformat=sample_fmts=s16p"]
    }
}

// MARK: - Conversion Preset

struct ConversionPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var outputFormat: OutputFormat = .mp3
    var bitrate: Int = 320
    var videoCRF: Int = 23
    var ditherMethod: DitherMethod = .shibata
    var outputFolderPath: String? = nil
    var filenameTemplate: String = "{name}"

    static let `default` = ConversionPreset(name: "Default MP3 320k")

    var outputFolder: URL? {
        get { outputFolderPath.map { URL(fileURLWithPath: $0) } }
        set { outputFolderPath = newValue?.path }
    }

    func outputURL(for inputURL: URL) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let filename = applyTemplate(name: baseName)
        let folder   = outputFolder ?? inputURL.deletingLastPathComponent()
        let ext      = outputFormat.fileExtension
        var url = folder.appendingPathComponent(filename).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(filename)_\(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    func previewFilename(example: String = "my_file") -> String {
        applyTemplate(name: example) + "." + outputFormat.fileExtension
    }

    func ffmpegArgs(inputPath: String, outputPath: String, hasVideoInput: Bool) -> [String] {
        var args: [String] = ["-y", "-i", inputPath]

        if outputFormat == .gif {
            args += [
                "-filter_complex",
                "[0:v]fps=10,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
                "-loop", "0", "-an"
            ]
            args.append(outputPath)
            return args
        }

        if outputFormat.isVideo {
            if hasVideoInput {
                args += outputFormat.videoCodecArgs
                args += ["-crf", "\(videoCRF)"]
            } else {
                args += ["-vn"]
            }
        } else {
            args += ["-vn"]
            if !outputFormat.isLossless {
                args += ditherMethod.ffmpegFilterArgs
            }
        }

        if outputFormat.supportsAudio {
            args += outputFormat.audioCodecArgs
            if !outputFormat.isLossless {
                args += ["-b:a", "\(bitrate)k"]
            }
        }

        args.append(outputPath)
        return args
    }

    private func applyTemplate(name: String) -> String {
        var s = filenameTemplate.isEmpty ? "{name}" : filenameTemplate
        s = s.replacingOccurrences(of: "{name}",    with: name)
        s = s.replacingOccurrences(of: "{bitrate}", with: "\(bitrate)")
        s = s.replacingOccurrences(of: "{format}",  with: outputFormat.rawValue)
        s = s.replacingOccurrences(of: "{dither}",  with: ditherMethod.rawValue)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        s = s.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
        return s
    }

    // Custom decoder for backward compatibility with v2 presets (no outputFormat / videoCRF)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self, forKey: .id)
        name             = try c.decode(String.self, forKey: .name)
        outputFormat     = try c.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .mp3
        bitrate          = try c.decodeIfPresent(Int.self, forKey: .bitrate) ?? 320
        videoCRF         = try c.decodeIfPresent(Int.self, forKey: .videoCRF) ?? 23
        ditherMethod     = try c.decodeIfPresent(DitherMethod.self, forKey: .ditherMethod) ?? .shibata
        outputFolderPath = try c.decodeIfPresent(String.self, forKey: .outputFolderPath)
        filenameTemplate = try c.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? "{name}"
    }

    init(id: UUID = UUID(), name: String, outputFormat: OutputFormat = .mp3,
         bitrate: Int = 320, videoCRF: Int = 23, ditherMethod: DitherMethod = .shibata,
         outputFolderPath: String? = nil, filenameTemplate: String = "{name}") {
        self.id              = id
        self.name            = name
        self.outputFormat    = outputFormat
        self.bitrate         = bitrate
        self.videoCRF        = videoCRF
        self.ditherMethod    = ditherMethod
        self.outputFolderPath = outputFolderPath
        self.filenameTemplate = filenameTemplate
    }
}

// MARK: - Preset Store

@Observable
final class PresetStore {
    var presets: [ConversionPreset] = []
    var selectedID: UUID

    private let presetsKey  = "v3.presets"
    private let selectedKey = "v3.selectedPresetID"

    var selected: ConversionPreset {
        get { presets.first { $0.id == selectedID } ?? presets[0] }
        set {
            guard let idx = presets.firstIndex(where: { $0.id == newValue.id }) else { return }
            presets[idx] = newValue
            save()
        }
    }

    init() {
        let builtIn: [ConversionPreset] = [
            ConversionPreset(id: UUID(), name: "MP3 320k",
                             outputFormat: .mp3, bitrate: 320, ditherMethod: .shibata),
            ConversionPreset(id: UUID(), name: "AAC 256k",
                             outputFormat: .aac, bitrate: 256, ditherMethod: .none),
            ConversionPreset(id: UUID(), name: "FLAC",
                             outputFormat: .flac, ditherMethod: .none),
            ConversionPreset(id: UUID(), name: "MP4 H.264",
                             outputFormat: .mp4, bitrate: 192, videoCRF: 23, ditherMethod: .none),
        ]

        // Try v3 first, then migrate from v2 (outputFormat defaults to .mp3)
        let loadedPresets: [ConversionPreset]
        if let data    = UserDefaults.standard.data(forKey: "v3.presets"),
           let decoded = try? JSONDecoder().decode([ConversionPreset].self, from: data),
           !decoded.isEmpty {
            loadedPresets = decoded
        } else if let data    = UserDefaults.standard.data(forKey: "v2.presets"),
                  let decoded = try? JSONDecoder().decode([ConversionPreset].self, from: data),
                  !decoded.isEmpty {
            loadedPresets = decoded
        } else {
            loadedPresets = builtIn
        }

        let resolvedID: UUID
        let selectedRaw = UserDefaults.standard.string(forKey: "v3.selectedPresetID")
                       ?? UserDefaults.standard.string(forKey: "v2.selectedPresetID")
        if let raw  = selectedRaw,
           let uuid = UUID(uuidString: raw),
           loadedPresets.contains(where: { $0.id == uuid }) {
            resolvedID = uuid
        } else {
            resolvedID = loadedPresets[0].id
        }

        self.presets    = loadedPresets
        self.selectedID = resolvedID
    }

    func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
        UserDefaults.standard.set(selectedID.uuidString, forKey: selectedKey)
    }

    func addNew(copying source: ConversionPreset? = nil) {
        var copy    = source ?? .default
        copy.id     = UUID()
        copy.name   = (source?.name ?? "New Preset") + " Copy"
        presets.append(copy)
        selectedID = copy.id
        save()
    }

    func deleteSelected() {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == selectedID }
        selectedID = presets[0].id
        save()
    }
}
