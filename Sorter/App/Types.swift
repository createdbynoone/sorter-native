import Foundation
import SwiftUI

enum Status: String, Codable, CaseIterable, Identifiable {
    case unsorted, keep, maybe, discard, archived
    var id: String { rawValue }

    var label: String { rawValue.capitalized }
    var key: String {
        switch self { case .keep: return "K"; case .maybe: return "M"; case .discard: return "D"; case .archived: return "A"; case .unsorted: return "U" }
    }
    var symbol: String {
        switch self {
        case .keep: return "arrow.up"
        case .maybe: return "tilde"
        case .discard: return "xmark"
        case .archived: return "archivebox"
        case .unsorted: return "circle.dotted"
        }
    }
    var color: Color {
        switch self {
        case .keep: return Theme.ok
        case .maybe: return Theme.accent
        case .discard: return Theme.danger
        case .archived: return Theme.info
        case .unsorted: return Theme.secondary
        }
    }
    var sortOrder: Int { [.keep, .maybe, .unsorted, .discard, .archived].firstIndex(of: self)! }
}

enum Source: String, Codable { case desktop, folder, drop }

struct MediaEntry: Codable, Identifiable, Hashable {
    var path: String
    var fingerprint: String
    var status: Status
    var rating: Int
    var categories: [String]
    var note: String
    var source: Source
    var addedAt: Double      // ms since epoch (shared format with the Electron build)
    var updatedAt: Double
    var missing: Bool?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var filename: String { (path as NSString).lastPathComponent }
    var isVideo: Bool { Media.isVideo(path) }
    var isMissing: Bool { missing ?? false }
    var added: Date { Date(timeIntervalSince1970: addedAt / 1000) }
}

struct Category: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String?
    var parentId: String?
    var createdAt: Double
    var isParent: Bool { parentId == nil }
}

struct SorterDB: Codable {
    var version: Int = 1
    var entries: [String: MediaEntry] = [:]
    var categories: [String: Category] = [:]
}

enum Filter: String, CaseIterable, Identifiable {
    case all, unsorted, keep, maybe, discard, archived
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var status: Status? { Status(rawValue: rawValue) }
}

enum SortKey: String, CaseIterable, Identifiable {
    case newest, oldest, status, name
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Media {
    static let videoExt: Set<String> = ["mp4", "mov", "webm", "m4v"]
    static let imageExt: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
    static var mediaExt: Set<String> { videoExt.union(imageExt) }

    static func isVideo(_ p: String) -> Bool { videoExt.contains((p as NSString).pathExtension.lowercased()) }
    static func isMedia(_ p: String) -> Bool { mediaExt.contains((p as NSString).pathExtension.lowercased()) }
    /// Files BMP writes: bmp_*.{jpg,png,webp,mp4,mov,webm}
    static func isBMPOutput(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasPrefix("bmp_") else { return false }
        let ext = (lower as NSString).pathExtension
        return ["jpg", "jpeg", "png", "webp", "mp4", "mov", "webm"].contains(ext)
    }
}

let gridSizes: [CGFloat] = [120, 160, 220, 300, 400]
