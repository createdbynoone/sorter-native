import Foundation
import Observation

// JSON-backed DB (same file/shape as the Electron build). Writes are debounced,
// encoded off the main thread, and flushed synchronously on quit.
@MainActor
@Observable
final class Store {
    private(set) var db = SorterDB()
    /// Bumped on every DB change — AppModel memoizes its derived lists on it.
    private(set) var revision = 0
    @ObservationIgnored private var flushTimer: Timer?
    @ObservationIgnored private let io = DispatchQueue(label: "sorter.store.io", qos: .utility)

    static let defaultCategories = ["Fisher Hats", "Caps", "Tees", "Hoodies", "Shorts", "Sweatpants", "Jackets", "Cultural Revelations", "Essentials"]

    func load() {
        if let data = try? Data(contentsOf: AppPaths.db),
           let decoded = try? JSONDecoder().decode(SorterDB.self, from: data) {
            db = decoded
        } else {
            db = SorterDB()
        }
        revision &+= 1
        if db.categories.isEmpty {
            for name in Self.defaultCategories {
                let id = Self.uniqueId()
                db.categories[id] = Category(id: id, name: name, color: nil, parentId: nil, createdAt: Date().timeIntervalSince1970 * 1000)
            }
            touch()
        }
    }

    /// Every mutation goes through here: invalidates derived caches and debounces the write.
    private func touch() {
        revision &+= 1
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Snapshot the value-type DB and encode/write it on the io queue (serial → writes stay ordered).
    func flush() {
        flushTimer?.invalidate(); flushTimer = nil
        let snapshot = db
        io.async { Self.write(snapshot) }
    }

    /// Blocking flush for app termination — the serial queue drains any in-flight write first.
    func flushSync() {
        flushTimer?.invalidate(); flushTimer = nil
        let snapshot = db
        io.sync { Self.write(snapshot) }
    }

    nonisolated private static func write(_ db: SorterDB) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(db) { try? data.write(to: AppPaths.db, options: .atomic) }
    }

    static func uniqueId() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))-\(String(UUID().uuidString.prefix(5)).lowercased())"
    }

    // ── Fingerprint & reconcile ───────────────────────────────────────────

    static func fingerprint(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else { return "" }
        let birth = (attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size):\(Int((birth * 1000).rounded()))"
    }

    /// Adds new paths, re-links moved files by fingerprint, flags missing desktop files.
    @discardableResult
    func reconcile(_ diskPaths: [String], source: Source) -> [MediaEntry] {
        var byFingerprint: [String: MediaEntry] = [:]
        for e in db.entries.values where !e.fingerprint.isEmpty { byFingerprint[e.fingerprint] = e }

        let diskSet = Set(diskPaths)
        var seen = Set<String>()
        var added: [MediaEntry] = []
        let now = Date().timeIntervalSince1970 * 1000

        for path in diskPaths {
            if var e = db.entries[path] {
                e.fingerprint = Self.fingerprint(path); e.missing = false
                db.entries[path] = e; seen.insert(path)
            } else {
                let fp = Self.fingerprint(path)
                if !fp.isEmpty, var moved = byFingerprint[fp], !diskSet.contains(moved.path) {
                    db.entries.removeValue(forKey: moved.path)
                    moved.path = path; moved.fingerprint = fp; moved.missing = false
                    db.entries[path] = moved; seen.insert(path)
                } else {
                    let e = MediaEntry(path: path, fingerprint: fp, status: .unsorted, rating: 0, categories: [], note: "",
                                       source: source, addedAt: now, updatedAt: now, missing: false)
                    db.entries[path] = e; added.append(e); seen.insert(path)
                }
            }
        }

        if source == .desktop {
            for (path, e) in db.entries where !seen.contains(path) && e.source == .desktop {
                db.entries[path]?.missing = !FileManager.default.fileExists(atPath: path)
            }
        }
        touch()
        return added
    }

    // ── Mutations ─────────────────────────────────────────────────────────

    func mutate(_ path: String, _ fn: (inout MediaEntry) -> Void) {
        guard var e = db.entries[path] else { return }
        fn(&e)
        e.updatedAt = Date().timeIntervalSince1970 * 1000
        db.entries[path] = e
        touch()
    }

    func addCategory(name: String, parentId: String? = nil) -> Category? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= 80 else { return nil }
        if let parentId, db.categories[parentId] == nil { return nil }
        let id = Self.uniqueId()
        let c = Category(id: id, name: n, color: nil, parentId: parentId, createdAt: Date().timeIntervalSince1970 * 1000)
        db.categories[id] = c
        touch()
        return c
    }

    func renameCategory(_ id: String, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, db.categories[id] != nil else { return }
        db.categories[id]?.name = n
        touch()
    }

    func deleteCategory(_ id: String) {
        guard db.categories[id] != nil else { return }
        var ids = Set([id])
        for (k, c) in db.categories where c.parentId == id { ids.insert(k) }
        for k in ids { db.categories.removeValue(forKey: k) }
        for (path, e) in db.entries where !Set(e.categories).isDisjoint(with: ids) {
            db.entries[path]?.categories = e.categories.filter { !ids.contains($0) }
        }
        touch()
    }

    func purgeMissing() {
        for (path, e) in db.entries where e.isMissing { db.entries.removeValue(forKey: path) }
        touch()
    }

    func remove(_ path: String) { db.entries.removeValue(forKey: path); touch() }

    // ── Library ───────────────────────────────────────────────────────────

    /// Expands folders to their media files; passes media files through.
    static func expand(_ paths: [String]) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        for p in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                for f in (try? fm.contentsOfDirectory(atPath: p)) ?? [] where Media.isMedia(f) { out.append((p as NSString).appendingPathComponent(f)) }
            } else if Media.isMedia(p) {
                out.append(p)
            }
        }
        return out
    }

    /// Copies an external file into the managed library (dedup by name+size).
    static func copyToLibrary(_ src: String) -> String {
        let fm = FileManager.default
        let dir = AppPaths.library
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (src as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var dest = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) {
            let srcSize = (try? fm.attributesOfItem(atPath: src)[.size] as? Int) ?? -1
            let dstSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -2
            if srcSize == dstSize { return dest.path }
            var i = 1
            while fm.fileExists(atPath: dir.appendingPathComponent("\(base)_\(i).\(ext)").path) { i += 1 }
            dest = dir.appendingPathComponent("\(base)_\(i).\(ext)")
        }
        try? fm.copyItem(atPath: src, toPath: dest.path)
        return dest.path
    }
}
