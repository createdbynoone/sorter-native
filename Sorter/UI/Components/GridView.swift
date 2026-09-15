import SwiftUI
import AppKit

struct GridView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var columns: Int = 5

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView { content(height: geo.size.height) }
                    .onChange(of: model.anchor) { _, a in
                        if let a { withAnimation(Theme.ease) { proxy.scrollTo(a) } }
                    }
            }
            .onChange(of: geo.size.width, initial: true) { _, w in recomputeColumns(width: w) }
            .onChange(of: model.gridSize) { _, _ in recomputeColumns(width: geo.size.width) }
        }
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture { model.clearSelection(); focused = true }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .modifier(GridKeys(columns: columns))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await FileDrop.urls(from: providers)
                if !urls.isEmpty { await MainActor.run { model.importPaths(urls) } }
            }
            return true
        }
    }

    private func recomputeColumns(width: CGFloat) {
        columns = max(1, Int((width - 24 + 8) / (model.gridSize + 8)))
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        let list = model.filtered
        if list.isEmpty {
            EmptyGrid(hasEntries: !model.entries.isEmpty).frame(maxWidth: .infinity, minHeight: height - 40)
        } else if let groups = model.grouped {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(groups) { g in GroupSection(group: g) }
            }
            .padding(12)
        } else {
            CardGrid(entries: list).padding(12)
        }
    }
}

// ── Pieces ────────────────────────────────────────────────────────────────

private struct EmptyGrid: View {
    let hasEntries: Bool
    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 36, color: Theme.muted)
            Text(hasEntries ? "No images match the filters" : "Drop images, videos or folders · Import · auto-scans BMP's output folder")
                .font(Theme.mono(11)).tracking(0.8).foregroundStyle(Theme.muted)
        }
    }
}

private struct GroupSection: View {
    @Environment(AppModel.self) private var model
    let group: AppModel.Group

    private var collapsed: Bool { model.collapsedGroups.contains(group.id) }
    private var products: Int { group.subGroups.filter { $0.catId != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(Theme.ease) {
                    if collapsed { model.collapsedGroups.remove(group.id) } else { model.collapsedGroups.insert(group.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(group.name.uppercased()).font(.system(size: 11.5, weight: .bold)).tracking(2).foregroundStyle(Theme.text)
                    Text("\(group.count)").font(Theme.mono(11)).foregroundStyle(Theme.muted).monospacedDigit()
                    if products > 0 {
                        Text("· \(products) producto\(products == 1 ? "" : "s")").font(Theme.mono(11)).foregroundStyle(Theme.muted.opacity(0.7))
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(group.subGroups) { sub in SubGroupSection(sub: sub) }
            }
        }
    }
}

private struct SubGroupSection: View {
    let sub: AppModel.SubGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sub.catId != nil {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent.opacity(0.7)).frame(width: 4, height: 4)
                    Text(sub.name.uppercased()).font(Theme.mono(10.5)).tracking(1.2).foregroundStyle(Theme.secondary)
                    Text("\(sub.entries.count)").font(Theme.mono(10.5)).foregroundStyle(Theme.muted.opacity(0.7))
                    Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 1)
                }
            }
            CardGrid(entries: sub.entries)
        }
    }
}

private struct CardGrid: View {
    @Environment(AppModel.self) private var model
    let entries: [MediaEntry]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: model.gridSize, maximum: model.gridSize * 1.6), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(entries) { e in CardCell(entry: e).id(e.path) }
        }
    }
}

private struct CardCell: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry

    var body: some View {
        MediaCard(entry: entry, categories: model.categories,
                  selected: model.selected.contains(entry.path),
                  primary: model.anchor == entry.path,
                  isNew: model.newPaths.contains(entry.path))
            .onTapGesture(count: 2) { model.openFocus(entry.path) }
            .onTapGesture {
                let f = NSEvent.modifierFlags
                model.click(entry.path, command: f.contains(.command), shift: f.contains(.shift))
            }
            .contextMenu { CardMenu(entry: entry) }
    }
}

private struct CardMenu: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry

    var body: some View {
        let targets = model.contextTarget(entry.path)
        let many = targets.count > 1
        let allArchived = targets.allSatisfy { model.entries[$0]?.status == .archived }
        let allDiscard = targets.allSatisfy { model.entries[$0]?.status == .discard }
        Button(many ? "Open \(targets.count) files" : "Open") { targets.forEach { model.open($0) } }
        Button("Reveal in Finder") { model.reveal(targets[0]) }
        Divider()
        Menu("Status") {
            ForEach(Status.allCases) { s in Button(s.label) { model.setStatus(targets, s) } }
        }
        Button(allArchived ? "Unarchive" : "Archive") { model.toggleStatus(targets, .archived) }
        Button(allDiscard ? "Undiscard" : "Discard") { model.toggleStatus(targets, .discard) }
        if !many && !entry.isVideo {
            Divider()
            Button("Export…") { model.exportEntry = entry }
        }
    }
}

// Keyboard triage while the grid has focus (text fields keep their own focus, so
// typing in the note/search never triggers these).
private struct GridKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let columns: Int

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) { model.moveAnchor(by: -1, columns: columns); return .handled }
            .onKeyPress(.downArrow) { model.moveAnchor(by: 1, columns: columns); return .handled }
            .onKeyPress(.leftArrow) { model.moveAnchor(by: -1); return .handled }
            .onKeyPress(.rightArrow) { model.moveAnchor(by: 1); return .handled }
            .onKeyPress(.return) { model.openFocus(); return .handled }
            .onKeyPress(.escape) { if model.selected.count > 1 { model.clearSelection() }; return .handled }
            .onKeyPress(characters: .alphanumerics.union(CharacterSet(charactersIn: "[]"))) { press in handle(press) }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isSubset(of: [.shift]) else { return .ignored }
        switch press.characters.lowercased() {
        case "k": status(.keep)
        case "m": status(.maybe)
        case "d": status(.discard)
        case "u": status(.unsorted)
        case "a": status(.archived)
        case "f": model.openFocus()
        case "n": if model.anchor != nil { model.focusNote = true; model.inspectorOpen = true }
        case "r": if let a = model.anchor { model.reveal(a) }
        case "i": model.inspectorOpen.toggle(); model.savePrefs()
        case "[": model.stepGrid(-1)
        case "]": model.stepGrid(1)
        default: return .ignored
        }
        return .handled
    }

    private func status(_ s: Status) {
        if model.selected.count > 1 { model.setStatus(model.selected, s) }
        else if let a = model.anchor { model.setStatus(a, s) }
    }
}

enum FileDrop {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
            let url: URL? = await withCheckedContinuation { cont in
                p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    if let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) { cont.resume(returning: u) }
                    else if let u = item as? URL { cont.resume(returning: u) }
                    else { cont.resume(returning: nil) }
                }
            }
            if let url { out.append(url) }
        }
        return out
    }
}
