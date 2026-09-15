import Foundation
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

// Thumbnails: 400px long side, JPEG on disk keyed by fingerprint, NSCache in
// memory. Video frames come from AVAssetImageGenerator (no ffmpeg needed).
//
// All decoding happens inside nonisolated async functions, which Swift runs on
// the cooperative pool — never on the main actor — so the first draw of a card
// is a blit of an already-decoded bitmap, not a JPEG decode on the UI thread.
enum Thumbs {
    // A 400px thumb is ~0.5–0.8 MB decoded; cap the cache by bytes so memory
    // stays flat no matter how big the library gets.
    private static let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()
    private static let maxSide = 400

    private static func cacheURL(for path: String, fingerprint: String) -> URL {
        let key = fingerprint.isEmpty ? path : fingerprint
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return AppPaths.thumbs.appendingPathComponent("\(hash).jpg")
    }

    static func cached(_ path: String) -> NSImage? { memory.object(forKey: path as NSString) }

    static func load(_ path: String, fingerprint: String) async -> NSImage? {
        if let hit = cached(path) { return hit }
        // Card scrolled out of view before we started — don't decode for nothing.
        if Task.isCancelled { return nil }
        let url = cacheURL(for: path, fingerprint: fingerprint)
        let cg: CGImage?
        if FileManager.default.fileExists(atPath: url.path) {
            cg = downsample(url.path)
        } else {
            try? FileManager.default.createDirectory(at: AppPaths.thumbs, withIntermediateDirectories: true)
            cg = Media.isVideo(path) ? await videoFrame(path) : downsample(path)
            if let cg { write(cg, to: url) }
        }
        guard let cg else { return nil }
        return store(cg, for: path)
    }

    private static func store(_ cg: CGImage, for path: String) -> NSImage {
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(image, forKey: path as NSString, cost: cg.bytesPerRow * cg.height)
        return image
    }

    /// Decoded bitmap, long side ≤ maxPixel, orientation applied.
    static func downsample(_ path: String, maxPixel: Int = maxSide) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Display-ready image for Focus. Capped at 4096px: that's already the largest
    /// size BMP produces, and it keeps a stray 8K drop from allocating ~250 MB.
    static func full(_ path: String, maxPixel: Int = 4096) async -> NSImage? {
        guard let cg = downsample(path, maxPixel: maxPixel) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func videoFrame(_ path: String) async -> CGImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSide, height: maxSide)
        let duration = (try? await asset.load(.duration))?.seconds ?? 2
        let t = CMTime(seconds: min(1, duration / 3), preferredTimescale: 600)
        return try? await gen.image(at: t).image
    }

    private static func write(_ cg: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Full-resolution pixel size (images) or size + duration (video) for the inspector.
    static func info(_ path: String) async -> String {
        if Media.isVideo(path) {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  let dur = try? await asset.load(.duration) else { return "" }
            let s = Int(dur.seconds.rounded())
            return "\(Int(abs(size.width))) × \(Int(abs(size.height))) · \(s / 60):\(String(format: "%02d", s % 60))"
        }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return "" }
        return "\(w) × \(h)"
    }
}
