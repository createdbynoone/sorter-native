import SwiftUI
import AppKit

// Pulsing dot driven by Core Animation. A SwiftUI `repeatForever` animation keeps
// the entire view graph re-rendering at display rate for as long as it runs
// (measured ~45 % CPU on an idle grid); a CABasicAnimation on a layer costs the
// main thread nothing — the render server does the fading.
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
