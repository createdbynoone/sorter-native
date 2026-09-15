import SwiftUI
import AppKit

// Pulsing dot driven by Core Animation. A SwiftUI `repeatForever` animation keeps
// the entire view graph re-rendering at display rate for as long as it runs
// (measured ~45 % CPU on an idle grid); a CABasicAnimation on a layer costs the
// main thread nothing — the render server does the fading.
// Floating inspector, mirroring the Electron build: a rounded Liquid Glass card
// inset from the edges that slides in over the content (never reflows it), and a
// 40pt round toggle centered vertically that slides along with it.
struct InspectorOverlay: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry?
    static let panelWidth: CGFloat = 280
    static let panelInset: CGFloat = 12
    static let toggleSize: CGFloat = 40
    static let toggleInset: CGFloat = 8
    private static let panelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    /// Trailing strip the marquee must leave alone while the panel is open.
    static let reservedWidth: CGFloat = panelWidth + panelInset + toggleInset + toggleSize + 8
    /// Same, for the toggle alone while the panel is closed.
    static let toggleReserved: CGFloat = toggleInset + toggleSize + 8

    @State private var hover = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if model.inspectorOpen {
                InspectorView(entry: entry, focusNote: model.focusNote)
                    .frame(width: Self.panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(GlassSurface(shape: Self.panelShape))
                    .clipShape(Self.panelShape)
                    .shadow(color: .black.opacity(0.3), radius: 28, y: 10)
                    .padding(Self.panelInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            toggle
                .padding(.trailing, model.inspectorOpen ? Self.panelWidth + Self.panelInset + Self.toggleInset : Self.toggleInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(Theme.ease, value: model.inspectorOpen)
    }

    private var toggle: some View {
        Button { model.inspectorOpen.toggle(); model.savePrefs() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(model.inspectorOpen ? 180 : 0))
                .foregroundStyle(hover ? Theme.text : Theme.secondary)
                .frame(width: Self.toggleSize, height: Self.toggleSize)
                .background(GlassSurface(shape: Circle(), interactive: true))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.ease, value: hover)
        .help(model.inspectorOpen ? "Hide inspector  I" : "Show inspector  I")
    }
}

// Native Liquid Glass on macOS 26+. A medium Theme.surface tint keeps the system
// refraction and transparency but stops photos from washing out the panel's text;
// `interactive` adds the press/hover response for controls. Below 26 it falls
// back to a translucent material.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var interactive = false
    var tint: Double = 0.55
    var body: some View {
        if #available(macOS 26, *) {
            let glass = Glass.regular.tint(Theme.surface.opacity(tint))
            Color.clear.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            shape.fill(Theme.surface.opacity(0.55)).background(.thinMaterial, in: shape)
        }
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
