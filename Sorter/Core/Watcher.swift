import Foundation

// Watches BMP's output folder for new/removed `bmp_*` files. Waits for the
// file size to settle before reporting (BMP downloads in place).
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var known = Set<String>()
    private let queue = DispatchQueue(label: "sorter.watch", qos: .utility)
    private let path: String
    private let onAdded: ([String]) -> Void
    private let onRemoved: ([String]) -> Void

    init(path: String, onAdded: @escaping ([String]) -> Void, onRemoved: @escaping ([String]) -> Void) {
        self.path = path; self.onAdded = onAdded; self.onRemoved = onRemoved
        known = Set(Self.listing(path))
        start()
    }

    private static func listing(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter(Media.isBMPOutput)
    }

    private func start() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { [fd = self.fd] in close(fd) }
        source = src
        src.resume()
    }

    private func scan() {
        let now = Set(Self.listing(path))
        let added = now.subtracting(known)
        let removed = known.subtracting(now)
        known = now
        if !removed.isEmpty { onRemoved(removed.map { (path as NSString).appendingPathComponent($0) }) }
        for name in added { waitStable((path as NSString).appendingPathComponent(name), prev: -1, checks: 0) }
    }

    private func waitStable(_ full: String, prev: Int, checks: Int) {
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: full)[.size] as? Int) ?? -1
            if size > 0 && size == prev { self.onAdded([full]) }
            else if checks < 12 { self.waitStable(full, prev: size, checks: checks + 1) }
        }
    }

    func stop() { source?.cancel(); source = nil }
    deinit { stop() }
}
