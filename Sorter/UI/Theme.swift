import SwiftUI

// One warm-dark palette, one accent. Hairlines instead of shadows; hierarchy
// comes from weight and tracking, not color.
enum Theme {
    static let bg        = Color(hex: 0x0B0B0A)
    static let surface   = Color(hex: 0x111110)
    static let raised    = Color(hex: 0x171716)
    static let hairline  = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.14)
    static let accent    = Color(hex: 0xF54F1B)   // Brotherhood orange
    static let info      = Color(hex: 0x6B8FB5)
    static let text      = Color(hex: 0xECE8DF)
    static let secondary = Color(hex: 0x8F8D87)
    static let muted     = Color(hex: 0x5C5B57)
    static let ok        = Color(hex: 0x6FB07F)
    static let warn      = Color(hex: 0xD9905A)
    static let danger    = Color(hex: 0xD26A5C)

    static let radius: CGFloat = 8
    static let radiusSmall: CGFloat = 6
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)

    // Typography. SF Pro carries the UI; hierarchy comes from weight and color, not
    // size. SF Mono is reserved for real data (paths, file names, timestamps,
    // dimensions). Numbers inside prose use .monospacedDigit() instead of mono.
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold) }   // eyebrows
    static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func medium(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular) } // metadata in prose
    static func mono(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// Section eyebrow: small caps, wide tracking, secondary tone.
struct Eyebrow: View {
    let text: String
    var hint: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(Theme.label(10.5))
                .tracking(1.4)
                .foregroundStyle(Theme.secondary)
            if let hint {
                Text(hint)
                    .font(Theme.caption(10.5))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct Hairline: View {
    var axis: Axis = .horizontal
    var body: some View {
        Rectangle().fill(Theme.hairline)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

// Hover tracking without re-rendering the whole tree
struct HoverModifier: ViewModifier {
    @Binding var hovering: Bool
    func body(content: Content) -> some View {
        content.onHover { h in withAnimation(Theme.ease) { hovering = h } }
    }
}

extension View {
    func trackHover(_ binding: Binding<Bool>) -> some View { modifier(HoverModifier(hovering: binding)) }
}
