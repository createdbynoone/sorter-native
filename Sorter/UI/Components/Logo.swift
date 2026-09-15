import SwiftUI

// Brotherhood isotype (template SVG in the asset catalog, tinted via foregroundStyle).
struct BrandMark: View {
    var size: CGFloat = 56
    var color: Color = Theme.text
    var body: some View {
        Image("Logo")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

// Splash shown for a beat on launch: mark fades in, then hands off to the lock/main view.
struct SplashView: View {
    let done: () -> Void
    @State private var shown = false
    var body: some View {
        ZStack {
            Theme.bg
            BrandMark(size: 72)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.96)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.6)) { shown = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.easeOut(duration: 0.25)) { shown = false }
                try? await Task.sleep(nanoseconds: 260_000_000)
                done()
            }
        }
    }
}
