import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Cover-crop (never letterbox) composites at the two Brotherhood sizes, JPEG 0.95.
enum Exporter {
    struct Size: Identifiable, Hashable {
        let key: String, name: String, w: Int, h: Int
        var id: String { key }
        var label: String { "\(w)×\(h)" }
    }
    static let sizes = [Size(key: "box", name: "Box", w: 1080, h: 1080), Size(key: "vertical", name: "Vertical", w: 1080, h: 1920)]

    static func compose(_ path: String, size: Size) -> Data? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let (w, h) = (size.w, size.h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        let scale = max(CGFloat(w) / CGFloat(img.width), CGFloat(h) / CGFloat(img.height))
        let sw = CGFloat(img.width) * scale, sh = CGFloat(img.height) * scale
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - sw) / 2, y: (CGFloat(h) - sh) / 2, width: sw, height: sh))
        guard let out = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Composes the selected sizes and saves them into a folder the user picks. Returns saved paths.
    @MainActor
    static func export(_ entry: MediaEntry, sizes selected: Set<String>) async throws -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Seleccioná la carpeta de destino"
        panel.prompt = "Export here"
        guard panel.runModal() == .OK, let dir = panel.url else { return [] }
        let base = (entry.filename as NSString).deletingPathExtension
        let path = entry.path
        let chosen = sizes.filter { selected.contains($0.key) }
        return try await Task.detached(priority: .userInitiated) {
            var saved: [String] = []
            for s in chosen {
                guard let data = compose(path, size: s) else { throw NSError(domain: "Sorter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo componer \(s.label)"]) }
                let out = dir.appendingPathComponent("\(base)_\(s.label).jpg")
                try data.write(to: out, options: .atomic)
                saved.append(out.path)
            }
            return saved
        }.value
    }
}

enum Trash {
    /// Moves to the volume-correct Trash via FileManager; returns true when the file is gone.
    static func trash(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { return true }
        return !FileManager.default.fileExists(atPath: path)
    }
}
