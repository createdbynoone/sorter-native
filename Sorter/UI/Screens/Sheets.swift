import SwiftUI
import AppKit

// ── Export ────────────────────────────────────────────────────────────────
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: MediaEntry
    @State private var sizes: Set<String> = ["box", "vertical"]
    @State private var exporting = false
    @State private var result: String? = nil
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Export", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(entry.filename).font(Theme.mono(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text("Cover-crop (sin bandas) a los tamaños Brotherhood, JPEG 95 %.").font(Theme.body(12)).foregroundStyle(Theme.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Exporter.sizes) { s in
                    Toggle(isOn: Binding(get: { sizes.contains(s.key) }, set: { on in if on { sizes.insert(s.key) } else { sizes.remove(s.key) } })) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.hairlineStrong)
                                .frame(width: s.w == s.h ? 14 : 9, height: 14)
                            Text(s.name).font(.system(size: 12.5, weight: .medium))
                            Text(s.label).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if let result {
                Text(result).font(Theme.mono(11)).foregroundStyle(failed ? Theme.danger : Theme.ok)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    exporting = true; result = nil; failed = false
                    Task {
                        do {
                            let saved = try await Exporter.export(entry, sizes: sizes)
                            if saved.isEmpty { result = "Cancelado"; failed = true }
                            else {
                                result = "\(saved.count) archivo\(saved.count == 1 ? "" : "s") exportado\(saved.count == 1 ? "" : "s") ✓"
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: saved[0])])
                                try? await Task.sleep(nanoseconds: 700_000_000)
                                dismiss()
                            }
                        } catch { result = error.localizedDescription; failed = true }
                        exporting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if exporting { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12) }
                        Text(exporting ? "Exporting…" : "Export \(sizes.count)")
                    }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(sizes.isEmpty || exporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// ── Settings (⌘,) ─────────────────────────────────────────────────────────
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section("Sources") {
                LabeledContent("BMP output folder") {
                    HStack(spacing: 8) {
                        Text(model.watchPath).font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 280, alignment: .trailing)
                        Button("Rescan") { model.rescan() }.controlSize(.small)
                    }
                }
                Text("Se lee de las preferencias de BMP; cambia la carpeta desde BMP → Settings.").font(.system(size: 11)).foregroundStyle(.secondary)
                LabeledContent("Library (dropped files)") {
                    Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.library) }.controlSize(.small)
                }
            }
            Section("Maintenance") {
                let missing = model.entries.values.filter(\.isMissing).count
                LabeledContent("Missing files", value: "\(missing)")
                Button("Purge missing entries") { model.store.purgeMissing() }.disabled(missing == 0)
                LabeledContent("Thumbnail cache") {
                    Button("Clear") { try? FileManager.default.removeItem(at: AppPaths.thumbs) }.controlSize(.small)
                }
                LabeledContent("Database") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.db]) }.controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
