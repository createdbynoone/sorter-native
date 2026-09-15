import SwiftUI

struct LockScreen: View {
    let appName: String
    let onUnlocked: () -> Void
    @State private var key = ""
    @State private var error = false
    @State private var shake = 0
    @State private var lockUntil: Double = AppLock.lockUntil
    @State private var now = Date().timeIntervalSince1970 * 1000
    @State private var checking = false
    @FocusState private var focused: Bool

    private var locked: Bool { lockUntil > now }
    private var secondsLeft: Int { max(0, Int(((lockUntil - now) / 1000).rounded(.up))) }

    private func submit() {
        guard !locked, !checking, !key.isEmpty else { return }
        checking = true
        let attempt = key
        Task.detached(priority: .userInitiated) {
            let ok = AppLock.verify(attempt)
            await MainActor.run {
                checking = false
                if ok { AppLock.clearFailures(); onUnlocked(); return }
                lockUntil = AppLock.registerFailure()
                error = true; key = ""
                withAnimation(.spring(duration: 0.35, bounce: 0.6)) { shake += 1 }
            }
        }
    }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                BrandMark(size: 52)
                VStack(spacing: 4) {
                    Text(appName.uppercased()).font(.system(size: 12, weight: .bold)).tracking(2.5).foregroundStyle(Theme.text)
                    Text("Enter the key to unlock").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(spacing: 10) {
                SecureField("", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .disabled(locked || checking)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(error ? Theme.danger.opacity(0.6) : (focused ? Theme.accent.opacity(0.6) : Theme.hairline)))
                    .modifier(Shake(trigger: shake))
                    .onSubmit(submit)
                    .onChange(of: key) { _, _ in error = false }
                Group {
                    if locked { Text("Too many attempts · retry in \(secondsLeft)s").foregroundStyle(Theme.warn).monospacedDigit() }
                    else if error { Text("Wrong key").foregroundStyle(Theme.danger) }
                    else { Text(" ") }
                }
                .font(Theme.caption(11))
            }
            .frame(width: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear { focused = true }
        // Countdown ticks only while a lockout is active — an idle lock screen
        // runs no timer at all. Restarts when a failed attempt extends lockUntil.
        .task(id: lockUntil) {
            while !Task.isCancelled, lockUntil > Date().timeIntervalSince1970 * 1000 {
                now = Date().timeIntervalSince1970 * 1000
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            now = Date().timeIntervalSince1970 * 1000
        }
    }
}

struct Shake: ViewModifier, Animatable {
    var trigger: Int
    var animatableData: CGFloat { get { CGFloat(trigger) } set { phase = newValue } }
    private var phase: CGFloat = 0
    init(trigger: Int) { self.trigger = trigger; self.phase = CGFloat(trigger) }
    func body(content: Content) -> some View {
        content.offset(x: sin(phase * .pi * 6) * 5)
    }
}
