import SwiftUI
import AppKit

@main
struct SorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sorter", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 820, minHeight: 540)
                .onAppear { delegate.model = model }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Triage") {
                Button("Focus view") { model.openFocus() }.keyboardShortcut(.return, modifiers: .command).disabled(model.anchor == nil)
                Button("Back to grid") { model.closeFocus() }.keyboardShortcut(.escape, modifiers: .command).disabled(model.focusIndex == nil)
                Divider()
                Button("Select all") { model.selectAll() }.keyboardShortcut("a", modifiers: .command)
                Button("Deselect") { model.clearSelection() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Export…") { if let e = model.anchorEntry, !e.isVideo { model.exportEntry = e } }
                    .keyboardShortcut("e", modifiers: .command).disabled(model.anchorEntry?.isVideo ?? true)
                Button("Reveal in Finder") { if let a = model.anchor { model.reveal(a) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.anchor == nil)
                Divider()
                Button("Trash discarded…") { model.confirmTrash = true }
                    .keyboardShortcut(.delete, modifiers: .command).disabled((model.counts[.discard] ?? 0) == 0)
            }
        }

        Settings {
            SettingsView().environment(model).preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.store.flushSync() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var splashDone = false
    // Sorter's lock is first-run only: once the key was entered on this machine it doesn't ask again
    @State private var unlocked = Prefs.load().unlockedAt != nil

    var body: some View {
        ZStack {
            if !splashDone {
                SplashView { withAnimation(Theme.ease) { splashDone = true } }
                    .transition(.opacity)
            } else if unlocked {
                MainView()
                    .transition(.opacity)
                    .onAppear { model.boot() }
            } else {
                LockScreen(appName: "Sorter") { withAnimation(Theme.ease) { unlocked = true } }
                    .transition(.opacity)
            }
        }
        .background(Theme.bg)
        .background(WindowAccessor())
    }
}

// Keeps the native title bar but paints it with our background so the window
// reads as one surface (title, subtitle and toolbar buttons stay system-drawn).
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(Theme.bg)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
