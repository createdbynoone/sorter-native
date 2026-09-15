import SwiftUI
import AppKit

// Pulsing dot driven by Core Animation. A SwiftUI `repeatForever` animation keeps
// the entire view graph re-rendering at display rate for as long as it runs
// (measured ~45 % CPU on an idle grid); a CABasicAnimation on a layer costs the
// main thread nothing — the render server does the fading.
// Floating inspector, like the Electron build: a panel over the content (never
// pushes the grid) plus a floating toggle to collapse / expand it. The surface is
// near-opaque so images never bleed through the text.
struct InspectorOverlay: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry?
    static let panelWidth: CGFloat = 280
    static let reservedWidth: CGFloat = panelWidth + 12 + 8 + 30   // panel + gaps + toggle button

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.inspectorOpen.toggle(); model.savePrefs() } label: {
                Image(systemName: model.inspectorOpen ? "chevron.right" : "sidebar.trailing")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .background(surface(in: Circle()))
            .help(model.inspectorOpen ? "Hide inspector  I" : "Show inspector  I")

            if model.inspectorOpen {
                InspectorView(entry: entry, focusNote: model.focusNote)
                    .frame(width: Self.panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(surface(in: Self.shape))
                    .clipShape(Self.shape)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .animation(Theme.ease, value: model.inspectorOpen)
    }

    // Near-opaque surface (the "inactive window" look, always): a thin material
    // for edge vibrancy under a 94 % Theme.surface fill, so the images behind never
    // bleed into the panel's text.
    private func surface<S: InsettableShape>(in shape: S) -> some View {
        shape.fill(Theme.surface.opacity(0.94))
            .background(.thinMaterial, in: shape)
            .overlay(shape.strokeBorder(Theme.hairlineStrong))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }
}

struct PulseDot: NSViewRepresentable {
    var color: Color
    var size: CGFloat = 5
    var ring = false          // hairline ring instead of a filled dot

    func makeNSView(context: Context) -> PulseLayerView {
        let v = PulseLayerView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.apply(color: NSColor(color), size: size, ring: ring)
        return v
    }
    func updateNSView(_ v: PulseLayerView, context: Context) { v.apply(color: NSColor(color), size: size, ring: ring) }

    final class PulseLayerView: NSView {
        private var size: CGFloat = 5
        override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
        required init?(coder: NSCoder) { nil }

        func apply(color: NSColor, size: CGFloat, ring: Bool) {
            self.size = size
            guard let layer else { return }
            layer.cornerRadius = size / 2
            if ring { layer.borderColor = color.cgColor; layer.borderWidth = 1; layer.backgroundColor = nil }
            else { layer.backgroundColor = color.cgColor; layer.borderWidth = 0 }
            invalidateIntrinsicContentSize()
            pulse()
        }

        // CA drops animations when a layer leaves the tree — re-arm on every attach.
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pulse() }

        private func pulse() {
            guard let layer, window != nil, layer.animation(forKey: "pulse") == nil else { return }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.35
            a.duration = 0.9; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: "pulse")
        }
    }
}
