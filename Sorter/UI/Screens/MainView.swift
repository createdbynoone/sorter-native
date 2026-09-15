import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Group {
            if model.focusIndex != nil {
                FocusView().transition(.opacity)
            } else {
                GridView()
                    .overlay(alignment: .topTrailing) { InspectorOverlay(entry: model.anchorEntry) }
            }
        }
        .animation(Theme.ease, value: model.focusIndex == nil)
        .safeAreaInset(edge: .bottom, spacing: 0) { FooterBar() }
        .navigationTitle("Sorter")
        .navigationSubtitle(model.focusIndex == nil ? "Generation Triage" : "Focus")
        .toolbar { toolbar }
        .searchable(text: $m.search, placement: .toolbar, prompt: "Search name or note")
        .sheet(item: $m.exportEntry) { e in ExportSheet(entry: e) }
        .confirmationDialog("Move \(model.counts[.discard] ?? 0) discarded files to the Trash?", isPresented: $m.confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.trashDiscarded() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Files go to the Trash of their own volume; entries leave Sorter.") }
        .onChange(of: model.focusNote) { _, f in
            if f { Task { try? await Task.sleep(nanoseconds: 600_000_000); model.focusNote = false } }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Picker("Filter", selection: Binding(get: { model.filter }, set: { model.filter = $0; model.clearSelection() })) {
                ForEach(Filter.allCases) { f in
                    Text("\(f.label)  \(model.counts[f] ?? 0)").tag(f)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Filter by status")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort", selection: Binding(get: { model.sort }, set: { model.sort = $0 })) {
                    ForEach(SortKey.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Grid size", selection: Binding(get: { model.gridSize }, set: { model.gridSize = $0; model.savePrefs() })) {
                    ForEach(gridSizes, id: \.self) { s in Text("\(Int(s)) px").tag(s) }
                }
                .pickerStyle(.inline)
            } label: { Label("View", systemImage: "square.grid.2x2") }
            .help("Sort and grid size  [ ]")

            if (model.counts[.discard] ?? 0) > 0 {
                Button { model.confirmTrash = true } label: { Label("Trash \(model.counts[.discard] ?? 0)", systemImage: "trash") }
                    .help("Move discarded files to the Trash")
            }
            Button { model.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .help("Rescan BMP output folder  ⌘R").keyboardShortcut("r", modifiers: .command)
            Button { model.importFolder() } label: { Label("Import", systemImage: "folder.badge.plus") }
                .help("Import a folder  ⌘I").keyboardShortcut("i", modifiers: .command)
            Button { model.inspectorOpen.toggle(); model.savePrefs() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                .help("Toggle inspector  I")
        }
    }
}

struct FooterBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let c = model.statusCounts
        HStack(spacing: 10) {
            Text("\(model.entries.count) total").foregroundStyle(Theme.muted)
            if let n = c[.keep], n > 0 { Text("· ↑ \(n) keep").foregroundStyle(Theme.ok.opacity(0.8)) }
            if let n = c[.maybe], n > 0 { Text("· ~ \(n) maybe").foregroundStyle(Theme.accent.opacity(0.8)) }
            if let n = c[.discard], n > 0 { Text("· ✕ \(n) discard").foregroundStyle(Theme.danger.opacity(0.7)) }
            if let n = c[.unsorted], n > 0 { Text("· \(n) unsorted").foregroundStyle(Theme.muted) }
            if let n = c[.archived], n > 0 { Text("· ⬒ \(n) archived").foregroundStyle(Theme.info.opacity(0.8)) }
            if model.selected.count > 1 { Text("· \(model.selected.count) selected").foregroundStyle(Theme.text) }
            Spacer()
            Text((model.watchPath as NSString).abbreviatingWithTildeInPath).font(Theme.mono(10.5)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
            Text("v\(model.version)").foregroundStyle(Theme.muted)
        }
        .font(Theme.caption(11)).monospacedDigit()
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
