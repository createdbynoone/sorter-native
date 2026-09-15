import SwiftUI
import AVKit
import AppKit

// Full-window triage view: one item at a time, keyboard-first, inspector on the right.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var videoError = false

    private var entry: MediaEntry? {
        guard let i = model.focusIndex, model.filtered.indices.contains(i) else { return nil }
        return model.filtered[i]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider()
                ZStack {
                    Theme.bg
                    if let entry {
                        if entry.isVideo { videoView(entry) } else { imageView(entry) }
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) { InspectorOverlay(entry: entry) }
                Divider()
                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .focusable().focusEffectDisabled().focused($focused)
        .onAppear { focused = true }
        .onDisappear { player?.pause(); player = nil; image = nil }
        .task(id: entry?.path) { await loadMedia() }
        .onKeyPress(.leftArrow) { model.focusNavigate(-1); return .handled }
        .onKeyPress(.rightArrow) { model.focusNavigate(1); return .handled }
        .onKeyPress(.space) { model.focusNavigate(1); return .handled }
        .onKeyPress(.escape) { model.closeFocus(); return .handled }
        .onKeyPress(characters: .letters) { press in
            guard press.modifiers.isSubset(of: [.shift]), let e = entry else { return .ignored }
            switch press.characters.lowercased() {
            case "k": model.focusStatus(.keep)
            case "m": model.focusStatus(.maybe)
            case "d": model.focusStatus(.discard)
            case "u": model.focusStatus(.unsorted)
            case "a": model.focusStatus(.archived)
            case "n": model.focusNote = true; model.inspectorOpen = true
            case "r": model.reveal(e.path)
            case "e": if !e.isVideo { model.exportEntry = e }
            case "i": model.inspectorOpen.toggle(); model.savePrefs()
            default: return .ignored
            }
            return .handled
        }
    }

    // ── Media ─────────────────────────────────────────────────────────────
    private func loadMedia() async {
        zoom = 1; pan = .zero; videoError = false
        player?.pause(); player = nil; image = nil
        guard let entry else { return }
        if entry.isVideo {
            let p = AVPlayer(url: entry.url)
            p.isMuted = false
            player = p
            p.play()
        } else {
            // Decoded off-main and capped at 4K — NSImage(contentsOfFile:) would decode
            // the full file lazily on the main thread at first draw.
            image = await Thumbs.full(entry.path)
        }
        // Prefetch neighbours' thumbnails so grid/inspector feel instant
        for d in [-1, 1] {
            if let i = model.focusIndex, model.filtered.indices.contains(i + d) {
                let n = model.filtered[i + d]
                Task.detached(priority: .utility) { _ = await Thumbs.load(n.path, fingerprint: n.fingerprint) }
            }
        }
    }

    private func imageView(_ entry: MediaEntry) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .scaleEffect(zoom)
                    .offset(pan)
                    .gesture(DragGesture().onChanged { v in guard zoom > 1 else { return }; pan = CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height) }
                                          .onEnded { _ in panStart = pan })
                    .gesture(MagnifyGesture().onChanged { v in zoom = min(8, max(0.25, v.magnification)) }.onEnded { _ in if zoom <= 1 { pan = .zero; panStart = .zero } })
                    .onTapGesture(count: 2) { withAnimation(Theme.ease) { zoom = zoom > 1 ? 1 : 2; pan = .zero; panStart = .zero } }
                    .animation(.interactiveSpring(), value: pan)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScrollWheelZoom { delta in
            let factor: CGFloat = delta < 0 ? 1.12 : 1 / 1.12
            zoom = min(8, max(0.25, zoom * factor))
            if zoom <= 1 { pan = .zero; panStart = .zero }
        })
    }

    private func videoView(_ entry: MediaEntry) -> some View {
        Group {
            if let player, !videoError {
                VideoPlayer(player: player).padding(16)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "film").font(.system(size: 22)).foregroundStyle(Theme.muted)
                    Text("Can't decode this video here").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    Button("Reveal in Finder") { model.reveal(entry.path) }.controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Chrome ────────────────────────────────────────────────────────────
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeFocus() } label: { Label("Grid", systemImage: "chevron.left") }
                .buttonStyle(.accessoryBar).help("Back to grid  Esc")
            if let entry {
                StatusBadge(status: entry.status, size: 8)
                Text(entry.filename).font(Theme.mono(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let i = model.focusIndex {
                Text("\(i + 1) of \(model.filtered.count)").font(Theme.caption(11.5)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            HStack(spacing: 2) {
                Button { model.focusNavigate(-1) } label: { Image(systemName: "chevron.left") }.disabled((model.focusIndex ?? 0) <= 0)
                Button { model.focusNavigate(1) } label: { Image(systemName: "chevron.right") }.disabled((model.focusIndex ?? 0) >= model.filtered.count - 1)
            }
            .buttonStyle(.accessoryBar)
            if let entry, !entry.isVideo {
                Button { model.exportEntry = entry } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.accessoryBar).help("Export  E")
            }
            Button { model.inspectorOpen.toggle(); model.savePrefs() } label: { Image(systemName: "sidebar.trailing") }
                .buttonStyle(.accessoryBar).help("Inspector  I")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.bar)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            ForEach([Status.keep, .maybe, .discard, .archived, .unsorted]) { s in
                StatusPill(status: s, active: entry?.status == s) { model.focusStatus(s) }
            }
            Spacer()
            if zoom != 1 { Text("\(Int(zoom * 100))%").font(Theme.caption(11)).foregroundStyle(Theme.muted).monospacedDigit() }
            Text("← → navigate   K M D A U status   N note   E export").font(Theme.caption(11)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

// Scroll-wheel → zoom (SwiftUI has no wheel event; a tiny NSView underneath catches it).
struct ScrollWheelZoom: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> WheelView { let v = WheelView(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: WheelView, context: Context) { v.onScroll = onScroll }
    final class WheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
        override var acceptsFirstResponder: Bool { false }
    }
}
