import Foundation

// Same folder the Electron build uses (~/Library/Application Support/Sorter/) —
// the triage DB, lock state and library carry over between both apps.
enum AppPaths {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Sorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var db: URL { supportDir.appendingPathComponent("sorter-db.json") }
    static var prefs: URL { supportDir.appendingPathComponent("sorter-prefs.json") }
    static var library: URL { supportDir.appendingPathComponent("library", isDirectory: true) }
    // Own thumbnail cache (the Electron one stores 400px JPEGs keyed by a JS hash — not worth sharing)
    static var thumbs: URL { supportDir.appendingPathComponent("thumbs-native", isDirectory: true) }

    /// BMP's configured output folder, falling back to ~/Desktop.
    static func bmpOutputPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let prefs = base.appendingPathComponent("bmp/bmp-prefs.json")
        if let data = try? Data(contentsOf: prefs),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = (obj["outputPath"] as? String)?.trimmingCharacters(in: .whitespaces), !p.isEmpty,
           FileManager.default.fileExists(atPath: p) {
            return p
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    }
}

struct Prefs: Codable {
    var iconStyle: String = "Default"
    var unlockedAt: String?
    var authFailCount: Int?
    var authLockUntil: Double?
    var gridSize: Double?
    var inspectorOpen: Bool?

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: AppPaths.prefs),
              let decoded = try? JSONDecoder().decode(Prefs.self, from: data) else { return Prefs() }
        return decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: AppPaths.prefs, options: .atomic) }
    }
}
