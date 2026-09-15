import SwiftUI
import AppKit

struct StatusBadge: View {
    let status: Status
    var size: CGFloat = 9
    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(status == .maybe ? Theme.bg : .white)
            .frame(width: size * 2, height: size * 2)
            .background(Circle().fill(status.color))
    }
}

struct MediaCard: View {
    let entry: MediaEntry
    let categories: [String: Category]
    let selected: Bool
    let primary: Bool
    let isNew: Bool
    @State private var image: NSImage?
    @State private var loaded = false      // load finished (with or without an image)
    @State private var hover = false

    private var chips: [Category] { entry.categories.prefix(2).compactMap { categories[$0] } }

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.raised)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if loaded {
                // Missing or undecodable file: static glyph, no animation to keep alive.
                Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(Theme.muted)
            } else {
                PulseDot(color: Theme.hairlineStrong, size: 10, ring: true).frame(width: 10, height: 10)
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(alignment: .center) {
            if entry.isVideo {
                Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.status != .unsorted { StatusBadge(status: entry.status).padding(6) }
        }
        .overlay(alignment: .topLeading) {
            if entry.isMissing {
                Text("Missing").font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if hover && (!chips.isEmpty || !entry.note.isEmpty) {
                HStack(spacing: 4) {
                    if !entry.note.isEmpty { Circle().fill(Theme.accent).frame(width: 5, height: 5) }
                    Spacer()
                    ForEach(chips) { c in
                        Text(c.name).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.text.opacity(0.85)).lineLimit(1)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if entry.categories.count > 2 { Text("+\(entry.categories.count - 2)").font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.secondary).monospacedDigit() }
                }
                .padding(6)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .transition(.opacity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(selected ? Theme.accent : (hover ? Theme.hairlineStrong : Theme.hairline), lineWidth: selected ? 1.5 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous)
                .strokeBorder(Theme.accent.opacity(primary ? 0.35 : 0), lineWidth: 1).padding(-3)
        )
        .opacity(entry.status == .discard ? 0.4 : entry.status == .archived ? 0.6 : 1)
        .saturation(entry.status == .discard ? 0 : 1)
        .scaleEffect(isNew ? 1.03 : 1)
        .animation(Theme.ease, value: selected)
        .animation(Theme.ease, value: hover)
        .animation(.spring(duration: 0.5, bounce: 0.35), value: isNew)
        .onHover { hover = $0 }
        .task(id: entry.fingerprint + entry.path) {
            if let hit = Thumbs.cached(entry.path) { image = hit; loaded = true; return }
            let img = await Thumbs.load(entry.path, fingerprint: entry.fingerprint)
            guard !Task.isCancelled else { return }
            image = img; loaded = true
        }
        // Native drag-out: hands the ORIGINAL file to Finder/BMP/any drop target
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
    }
}
