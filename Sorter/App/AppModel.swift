import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    let store = Store()
    var unlocked = false
    var booted = false

    // ── View state ────────────────────────────────────────────────────────
    var filter: Filter = .all
    var sort: SortKey = .newest
    var search = ""
    var gridSize: CGFloat = 160
    var inspectorOpen = true
    var focusIndex: Int? = nil          // non-nil → Focus view
    var focusNote = false
    var exportEntry: MediaEntry? = nil
    var collapsedGroups = Set<String>()
    var scanning = false
    var newPaths = Set<String>()
    var watchPath = AppPaths.bmpOutputPath()
    var confirmTrash = false

    // ── Selection ─────────────────────────────────────────────────────────
    var selected = Set<String>()
    var anchor: String? = nil

    private var watcher: FolderWatcher?

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var entries: [String: MediaEntry] { store.db.entries }
    var categories: [String: Category] { store.db.categories }
    var anchorEntry: MediaEntry? { anchor.flatMap { entries[$0] } }

    // ── Derived lists ─────────────────────────────────────────────────────
    // Every list below is read many times per render (grid, focus, toolbar,
    // footer, key handlers). They're memoized on the store revision + the view
    // state they depend on, so a render costs one dictionary lookup instead of
    // a copy + filter + sort of the whole DB per access. Reading `store.revision`
    // and the view-state vars inside the getters keeps @Observable tracking intact.
    private struct ListKey: Equatable { let rev: Int; let filter: Filter; let sort: SortKey; let search: String }
    @ObservationIgnored private var filteredCache: (key: ListKey, list: [MediaEntry])?
    @ObservationIgnored private var groupedCache: (key: ListKey, groups: [Group]?)?
    @ObservationIgnored private var countsCache: (rev: Int, counts: [Filter: Int], status: [Status: Int])?

    private var listKey: ListKey { ListKey(rev: store.revision, filter: filter, sort: sort, search: search) }

    var filtered: [MediaEntry] {
        let key = listKey
        if let c = filteredCache, c.key == key { return c.list }
        let list = computeFiltered()
        filteredCache = (key, list)
        return list
    }

    private func computeFiltered() -> [MediaEntry] {
        var list = Array(entries.values)
        if let s = filter.status { list = list.filter { $0.status == s } }
        else { list = list.filter { $0.status != .archived } }   // 'All' hides archived on purpose
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.path.lowercased().contains(q) || $0.note.lowercased().contains(q) } }
        switch sort {
        case .newest: list.sort { $0.addedAt > $1.addedAt }
        case .oldest: list.sort { $0.addedAt < $1.addedAt }
        case .status: list.sort { ($0.status.sortOrder, -$0.addedAt) < ($1.status.sortOrder, -$1.addedAt) }
        case .name: list.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return list
    }

    struct SubGroup: Identifiable { let id: String; let catId: String?; let name: String; let entries: [MediaEntry] }
    struct Group: Identifiable { let id: String; let catId: String?; let name: String; let count: Int; let subGroups: [SubGroup] }

    /// Two-level category grouping — only in All with no search.
    var grouped: [Group]? {
        let key = listKey
        if let c = groupedCache, c.key == key { return c.groups }
        let groups = computeGrouped()
        groupedCache = (key, groups)
        return groups
    }

    private func computeGrouped() -> [Group]? {
        guard filter == .all, search.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let list = filtered
        let parents = categories.values.filter(\.isParent).sorted { $0.createdAt < $1.createdAt }
        let children = categories.values.filter { !$0.isParent }
        var groups: [Group] = []
        var assigned = Set<String>()
        for p in parents {
            let pe = list.filter { $0.categories.contains(p.id) }
            if pe.isEmpty { continue }
            var subs: [SubGroup] = []
            var subAssigned = Set<String>()
            for c in children.filter({ $0.parentId == p.id }).sorted(by: { $0.createdAt < $1.createdAt }) {
                let ce = pe.filter { $0.categories.contains(c.id) }
                if !ce.isEmpty { ce.forEach { subAssigned.insert($0.path) }; subs.append(SubGroup(id: c.id, catId: c.id, name: c.name, entries: ce)) }
            }
            let rest = pe.filter { !subAssigned.contains($0.path) }
            if !rest.isEmpty { subs.append(SubGroup(id: "\(p.id)__nosub", catId: nil, name: p.name, entries: rest)) }
            pe.forEach { assigned.insert($0.path) }
            groups.append(Group(id: p.id, catId: p.id, name: p.name, count: pe.count, subGroups: subs))
        }
        let uncat = list.filter { !assigned.contains($0.path) }
        if !uncat.isEmpty {
            groups.append(Group(id: "__uncat", catId: nil, name: "Sin categoría", count: uncat.count,
                                subGroups: [SubGroup(id: "__uncat_sub", catId: nil, name: "Sin categoría", entries: uncat)]))
        }
        return groups.isEmpty ? nil : groups
    }

    var counts: [Filter: Int] { derivedCounts().counts }
    var statusCounts: [Status: Int] { derivedCounts().status }

    /// One pass over the DB gives both the filter-bar counts and the footer counts.
    private func derivedCounts() -> (counts: [Filter: Int], status: [Status: Int]) {
        let rev = store.revision
        if let c = countsCache, c.rev == rev { return (c.counts, c.status) }
        var status: [Status: Int] = [:]
        for e in entries.values { status[e.status, default: 0] += 1 }
        var counts: [Filter: Int] = [.all: entries.count - (status[.archived] ?? 0)]
        for s in Status.allCases { counts[Filter(rawValue: s.rawValue)!] = status[s] ?? 0 }
        countsCache = (rev, counts, status)
        return (counts, status)
    }

    // ── Boot ──────────────────────────────────────────────────────────────
    func boot() {
        guard !booted else { return }
        booted = true
        let prefs = Prefs.load()
        if let g = prefs.gridSize, gridSizes.contains(CGFloat(g)) { gridSize = CGFloat(g) }
        if let o = prefs.inspectorOpen { inspectorOpen = o }
        store.load()
        rescan()
    }

    func savePrefs() {
        var p = Prefs.load(); p.gridSize = Double(gridSize); p.inspectorOpen = inspectorOpen; p.save()
    }

    func rescan() {
        scanning = true
        watchPath = AppPaths.bmpOutputPath()
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: watchPath)) ?? [])
            .filter(Media.isBMPOutput).map { (watchPath as NSString).appendingPathComponent($0) }
        store.reconcile(files, source: .desktop)
        startWatcher()
        scanning = false
    }

    private func startWatcher() {
        watcher?.stop()
        watcher = FolderWatcher(path: watchPath, onAdded: { [weak self] paths in
            Task { @MainActor in
                guard let self else { return }
                let added = self.store.reconcile(paths, source: .desktop)
                for e in added {
                    self.newPaths.insert(e.path)
                    Task { try? await Task.sleep(nanoseconds: 1_400_000_000); self.newPaths.remove(e.path) }
                }
            }
        }, onRemoved: { [weak self] paths in
            Task { @MainActor in
                guard let self else { return }
                for p in paths where self.entries[p] != nil { self.store.mutate(p) { $0.missing = true } }
            }
        })
    }

    // ── Import ────────────────────────────────────────────────────────────
    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Select a folder with generations"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.reconcile(Store.expand([url.path]), source: .folder)
    }

    func importPaths(_ urls: [URL]) {
        let raw = Store.expand(urls.map(\.path))
        let lib = AppPaths.library.path
        let files = raw.map { $0.hasPrefix(watchPath) || $0.hasPrefix(lib) ? $0 : Store.copyToLibrary($0) }
        let added = store.reconcile(files, source: .drop)
        for e in added {
            newPaths.insert(e.path)
            Task { try? await Task.sleep(nanoseconds: 1_400_000_000); newPaths.remove(e.path) }
        }
    }

    // ── Mutations ─────────────────────────────────────────────────────────
    func setStatus(_ path: String, _ s: Status) { store.mutate(path) { $0.status = s } }
    func setStatus(_ paths: some Collection<String>, _ s: Status) { for p in paths { setStatus(p, s) } }
    func setNote(_ path: String, _ n: String) { store.mutate(path) { $0.note = String(n.prefix(4000)) } }
    func setCategories(_ path: String, _ ids: [String]) { store.mutate(path) { $0.categories = ids.filter { self.categories[$0] != nil } } }

    /// Bulk-safe toggle: everything → target unless the whole selection already is, then back to unsorted.
    func toggleStatus(_ paths: [String], _ target: Status) {
        let all = paths.allSatisfy { entries[$0]?.status == target }
        setStatus(paths, all ? .unsorted : target)
    }

    /// One category + one product per entry (radio behaviour at each level).
    func toggleCategory(_ path: String, _ id: String) {
        guard let e = entries[path], let cat = categories[id] else { return }
        let currentParent = e.categories.first { categories[$0]?.isParent == true }
        if cat.isParent {
            setCategories(path, currentParent == id ? [] : [id])
        } else {
            let parent = currentParent ?? cat.parentId!
            let currentSub = e.categories.first { categories[$0]?.parentId == cat.parentId }
            setCategories(path, currentSub == id ? [parent] : [parent, id])
        }
    }

    func trashDiscarded() {
        let discarded = entries.values.filter { $0.status == .discard }
        for e in discarded {
            if !FileManager.default.fileExists(atPath: e.path) || Trash.trash(e.path) { store.remove(e.path) }
        }
        selected = selected.filter { entries[$0] != nil }
        if let a = anchor, entries[a] == nil { anchor = nil }
    }

    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    // ── Selection ─────────────────────────────────────────────────────────
    func click(_ path: String, command: Bool, shift: Bool) {
        if command {
            if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
            anchor = path
            return
        }
        if shift, let a = anchor {
            let list = filtered
            if let i = list.firstIndex(where: { $0.path == a }), let j = list.firstIndex(where: { $0.path == path }) {
                selected = Set(list[min(i, j)...max(i, j)].map(\.path))
                return
            }
        }
        selected = [path]; anchor = path
    }

    func selectAll() { selected = Set(filtered.map(\.path)) }
    func clearSelection() { selected = []; anchor = nil }

    /// Context-menu target: the whole multi-selection if the clicked card is part of it, else just that card.
    func contextTarget(_ path: String) -> [String] {
        selected.count > 1 && selected.contains(path) ? Array(selected) : [path]
    }

    func moveAnchor(by delta: Int, columns: Int = 1) {
        let list = filtered
        guard !list.isEmpty else { return }
        let i = anchor.flatMap { a in list.firstIndex { $0.path == a } } ?? -1
        let next = min(list.count - 1, max(0, i + delta * columns))
        anchor = list[next].path; selected = [list[next].path]
        if focusIndex != nil { focusIndex = next }
    }

    // ── Focus ─────────────────────────────────────────────────────────────
    func openFocus(_ path: String? = nil) {
        let p = path ?? anchor
        guard let p, let i = filtered.firstIndex(where: { $0.path == p }) else { return }
        selected = [p]; anchor = p; focusNote = false; focusIndex = i
    }

    func focusNavigate(_ delta: Int) {
        guard let i = focusIndex else { return }
        let n = i + delta
        guard n >= 0, n < filtered.count else { return }
        focusIndex = n; anchor = filtered[n].path; selected = [anchor!]; focusNote = false
    }

    func focusStatus(_ s: Status) {
        guard let i = focusIndex, i < filtered.count else { return }
        let p = filtered[i].path
        setStatus(p, s)
        // Auto-advance; when the filter drops the entry, the same index already points at the next one
        let stillThere = filtered.indices.contains(i) && filtered[i].path == p
        if stillThere { focusNavigate(1) } else if !filtered.indices.contains(i) { focusIndex = filtered.isEmpty ? nil : filtered.count - 1 }
        if let j = focusIndex, filtered.indices.contains(j) { anchor = filtered[j].path; selected = [anchor!] }
    }

    func closeFocus() { focusIndex = nil }

    func stepGrid(_ dir: Int) {
        guard let i = gridSizes.firstIndex(of: gridSize) else { gridSize = 160; return }
        let n = min(gridSizes.count - 1, max(0, i + dir))
        gridSize = gridSizes[n]; savePrefs()
    }
}
