import Foundation
import AppKit

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

    /// Returns ffmpeg -af arguments, or [] when dither is none.
    var ffmpegFilterArgs: [String] {
        if self == .none { return [] }
        return ["-af", "aresample=dither_method=\(rawValue),aformat=sample_fmts=s16p"]
    }
}

// MARK: - Conversion Preset

struct ConversionPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var bitrate: Int = 320
    var ditherMethod: DitherMethod = .shibata
    var outputFolderPath: String? = nil   // nil → same folder as source
    var filenameTemplate: String = "{name}"

    static let `default` = ConversionPreset(name: "Default 320k")

    var outputFolder: URL? {
        get { outputFolderPath.map { URL(fileURLWithPath: $0) } }
        set { outputFolderPath = newValue?.path }
    }

    func outputURL(for inputURL: URL) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let filename = applyTemplate(name: baseName)
        let folder   = outputFolder ?? inputURL.deletingLastPathComponent()
        var url = folder.appendingPathComponent(filename).appendingPathExtension("mp3")
        // Avoid collisions
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(filename)_\(n)").appendingPathExtension("mp3")
            n += 1
        }
        return url
    }

    func previewFilename(example: String = "my_song") -> String {
        applyTemplate(name: example) + ".mp3"
    }

    private func applyTemplate(name: String) -> String {
        var s = filenameTemplate.isEmpty ? "{name}" : filenameTemplate
        s = s.replacingOccurrences(of: "{name}",    with: name)
        s = s.replacingOccurrences(of: "{bitrate}", with: "\(bitrate)")
        s = s.replacingOccurrences(of: "{dither}",  with: ditherMethod.rawValue)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        s = s.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
        return s
    }
}

// MARK: - Preset Store

@Observable
final class PresetStore {
    var presets: [ConversionPreset] = []
    var selectedID: UUID

    private let presetsKey = "v2.presets"
    private let selectedKey = "v2.selectedPresetID"

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
            ConversionPreset(id: UUID(), name: "Default 320k",
                             bitrate: 320, ditherMethod: .shibata,
                             filenameTemplate: "{name}"),
            ConversionPreset(id: UUID(), name: "Podcast 128k",
                             bitrate: 128, ditherMethod: .triangular,
                             filenameTemplate: "{name}_podcast"),
            ConversionPreset(id: UUID(), name: "Streaming 256k",
                             bitrate: 256, ditherMethod: .shibata,
                             filenameTemplate: "{name}"),
        ]

        // Load presets into a local variable first (avoids @Observable init ordering issue)
        let loadedPresets: [ConversionPreset]
        if let data   = UserDefaults.standard.data(forKey: "v2.presets"),
           let decoded = try? JSONDecoder().decode([ConversionPreset].self, from: data),
           !decoded.isEmpty {
            loadedPresets = decoded
        } else {
            loadedPresets = builtIn
        }

        // Resolve selectedID before assigning to stored properties
        let resolvedID: UUID
        if let raw  = UserDefaults.standard.string(forKey: "v2.selectedPresetID"),
           let uuid = UUID(uuidString: raw),
           loadedPresets.contains(where: { $0.id == uuid }) {
            resolvedID = uuid
        } else {
            resolvedID = loadedPresets[0].id
        }

        // Now safe to assign (both stored properties initialized together)
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
