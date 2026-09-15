import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry?
    var focusNote = false

    var body: some View {
        if let entry {
            InspectorContent(entry: entry, focusNote: focusNote)
        } else {
            VStack(spacing: 10) {
                BrandMark(size: 28, color: Theme.muted)
                Text("Select an image to inspect").font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct InspectorContent: View {
    @Environment(AppModel.self) private var model
    let entry: MediaEntry
    let focusNote: Bool
    @State private var note = ""
    @State private var info = ""
    @State private var addingParent = false
    @State private var addingSubFor: String? = nil
    @State private var newName = ""
    @State private var renaming: Category? = nil
    @State private var renameValue = ""
    @State private var deleting: Category? = nil
    @FocusState private var noteFocused: Bool
    @FocusState private var newCatFocused: Bool

    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "es_CO"); f.dateFormat = "d MMM yyyy"; return f }()

    private var parents: [Category] { model.categories.values.filter(\.isParent).sorted { $0.createdAt < $1.createdAt } }
    private var activeParent: String? { entry.categories.first { model.categories[$0]?.isParent == true } }
    private var subs: [Category] {
        guard let p = activeParent else { return [] }
        return model.categories.values.filter { $0.parentId == p }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // File
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.filename).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2).truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(Self.df.string(from: entry.added))
                        if !info.isEmpty { Text("·"); Text(info) }
                        if entry.isVideo { Text("·"); Text("VIDEO") }
                    }
                    .font(Theme.caption(11)).foregroundStyle(Theme.secondary).monospacedDigit()
                    HStack(spacing: 6) {
                        Button("Reveal") { model.reveal(entry.path) }.help("Reveal in Finder  R")
                        Button("Open") { model.open(entry.path) }
                        if entry.isMissing { Text("Missing").font(Theme.caption(11)).foregroundStyle(Theme.warn) }
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }

                Divider()

                // Status
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Status")
                    FlowLayout(spacing: 4) {
                        ForEach([Status.keep, .maybe, .discard, .archived, .unsorted]) { s in
                            StatusPill(status: s, active: entry.status == s) { model.setStatus(entry.path, s) }
                        }
                    }
                }

                // Note
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Note", hint: "N")
                    TextEditor(text: $note)
                        .font(Theme.body(12.5))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70)
                        .padding(6)
                        .background(Theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(noteFocused ? Theme.text.opacity(0.3) : Theme.hairlineStrong))
                        .focused($noteFocused)
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty { Text("Anotar cambios, ideas…").font(Theme.body(12.5)).foregroundStyle(Theme.secondary).padding(11).allowsHitTesting(false) }
                        }
                }

                // Categories
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "Category")
                        Spacer()
                        Button { addingParent = true; addingSubFor = nil; newName = ""; newCatFocused = true } label: { Image(systemName: "plus") }
                            .buttonStyle(.accessoryBar).controlSize(.small).help("New category")
                    }
                    FlowLayout(spacing: 4) {
                        ForEach(parents) { c in chip(c, active: entry.categories.contains(c.id), muted: false) }
                        if addingParent { newField(parent: nil) }
                    }
                }

                if let p = activeParent {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Eyebrow(text: "Product")
                            Spacer()
                            Button { addingSubFor = p; addingParent = false; newName = ""; newCatFocused = true } label: { Image(systemName: "plus") }
                                .buttonStyle(.accessoryBar).controlSize(.small).help("New product")
                        }
                        FlowLayout(spacing: 4) {
                            ForEach(subs) { c in chip(c, active: entry.categories.contains(c.id), muted: true) }
                            if addingSubFor == p { newField(parent: p) }
                        }
                        if subs.isEmpty && addingSubFor != p {
                            Text("Sin productos. Agrega uno con +").font(Theme.caption(11)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .padding(14)
        }
        .task(id: entry.path) {
            note = entry.note
            info = ""
            info = await Thumbs.info(entry.path)
        }
        .onChange(of: note) { _, v in
            guard v != entry.note else { return }
            let path = entry.path
            Task { try? await Task.sleep(nanoseconds: 400_000_000); if note == v { model.setNote(path, v) } }
        }
        .onChange(of: focusNote) { _, f in if f { noteFocused = true } }
        .onAppear { if focusNote { noteFocused = true } }
        .alert("Delete \"\(deleting?.name ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let d = deleting { model.store.deleteCategory(d.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleting?.isParent == true ? "Its products are deleted too and every image loses this category." : "Every image loses this product.")
        }
    }

    @ViewBuilder
    private func chip(_ c: Category, active: Bool, muted: Bool) -> some View {
        if renaming?.id == c.id {
            TextField("", text: $renameValue)
                .textFieldStyle(.plain).font(Theme.body(11.5))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.hairlineStrong))
                .frame(width: 120)
                .onSubmit { model.store.renameCategory(c.id, renameValue); renaming = nil }
                .onExitCommand { renaming = nil }
        } else {
            Button { model.toggleCategory(entry.path, c.id) } label: {
                Text(c.name)
                    .font(Theme.medium(11.5))
                    .foregroundStyle(active ? Theme.accent : Theme.text.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(active ? Theme.accent.opacity(muted ? 0.12 : 0.16) : Theme.bg.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.hairlineStrong))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename") { renaming = c; renameValue = c.name }
                Button("Delete…", role: .destructive) { deleting = c }
            }
        }
    }

    private func newField(parent: String?) -> some View {
        TextField(parent == nil ? "New category…" : "New product…", text: $newName)
            .textFieldStyle(.plain).font(Theme.body(11.5))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.hairlineStrong))
            .frame(width: 130)
            .focused($newCatFocused)
            .onSubmit {
                if let c = model.store.addCategory(name: newName, parentId: parent) { model.toggleCategory(entry.path, c.id) }
                newName = ""; addingParent = false; addingSubFor = nil
            }
            .onExitCommand { newName = ""; addingParent = false; addingSubFor = nil }
    }
}

struct StatusPill: View {
    let status: Status
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: status.symbol).font(.system(size: 8.5, weight: .bold))
                Text(status.label).font(Theme.medium(11.5))
                Text(status.key).font(.system(size: 9, weight: .semibold)).opacity(0.5)
            }
            .foregroundStyle(active ? status.color : Theme.text.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(active ? status.color.opacity(0.16) : Theme.bg.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(active ? status.color.opacity(0.6) : Theme.hairlineStrong))
        }
        .buttonStyle(.plain)
    }
}

// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
