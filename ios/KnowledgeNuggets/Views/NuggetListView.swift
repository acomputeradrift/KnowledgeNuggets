import SwiftUI

/// What the editor sheet is editing.
enum EditorRoute: Identifiable {
    case new
    case edit(Nugget)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let nugget): return nugget.id.uuidString
        }
    }
}

struct NuggetListView: View {
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @State private var editor: EditorRoute?
    @State private var pendingDelete: Nugget?
    @State private var limitMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.isEmpty {
                    ContentUnavailableView {
                        Label("No Nuggets Yet", systemImage: "text.quote")
                    } description: {
                        Text("Add a passage you want to remember. Up to \(NuggetRules.activeLimit) can be in the daily rotation.")
                    } actions: {
                        Button("Add a Nugget") { editor = .new }
                            .primaryActionStyle()
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Nuggets")
            .toolbar {
                if model.all.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Label("Add Nugget", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { route in
                switch route {
                case .new: NuggetEditorView(nugget: nil)
                case .edit(let nugget): NuggetEditorView(nugget: nugget)
                }
            }
            .alert(
                "Delete Nugget?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { nugget in
                Button("Delete", role: .destructive) {
                    let deleted = withAnimation(.snappy) { model.delete(nugget) }
                    if deleted { toasts?.show("Nugget deleted") }
                }
                Button("Cancel", role: .cancel) {}
            } message: { nugget in
                Text(Self.deletePreview(nugget.text))
            }
            .alert(
                "Rotation Is Full",
                isPresented: Binding(
                    get: { limitMessage != nil },
                    set: { if !$0 { limitMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(limitMessage ?? "") }
            )
            .sensoryFeedback(.warning, trigger: limitMessage) { _, new in new != nil }
        }
    }

    private var layout: NuggetListLayout {
        NuggetListLayout(
            active: model.active.map(\.id),
            queued: model.queued.map(\.id),
            paused: model.paused.map(\.id)
        )
    }

    /// One `ForEach` over every row, so `onMove` can carry a nugget from any
    /// section to any other (it never leaves its `ForEach`, and its reorder
    /// drag never reaches another section's drop handler). Header rows can't
    /// be moved. Nugget rows keep the system background, so swipes look as
    /// they always have.
    private var list: some View {
        let layout = self.layout
        let byID = Dictionary(model.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return List {
            Section {
                ForEach(layout.rows) { item in
                    switch item {
                    case .header(let state):
                        SectionHeaderRow(state: state, activeCount: model.active.count)
                            .moveDisabled(true)
                    case .placeholder(let state):
                        Text(Self.emptyText(for: state))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .moveDisabled(true)
                    case .nugget(let id, _):
                        if let nugget = byID[id] {
                            nuggetRow(for: nugget)
                        }
                    }
                }
                .onMove { source, destination in
                    drop(source, at: destination, in: layout)
                }
            } header: {
                // A real section header, so the list's top corners round like
                // its bottom ones. Queued and Paused are header rows below.
                HStack(alignment: .firstTextBaseline) {
                    Text(NuggetState.active.title)
                    Spacer()
                    Text("\(model.active.count) of \(NuggetRules.activeLimit)")
                        .monospacedDigit()
                }
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Touch and hold a nugget to reorder it, or drag it to another section.")
            }
        }
        .listStyle(.insetGrouped)
    }

    static func emptyText(for state: NuggetState) -> String {
        switch state {
        case .active: return "No active nuggets. Swipe one below to Activate, or drag it here."
        case .queued: return "Nothing queued. New nuggets wait here when Active is full."
        case .paused: return "Nothing paused. Swipe an active nugget to Pause it."
        }
    }

    private func nuggetRow(for nugget: Nugget) -> some View {
        Button {
            editor = .edit(nugget)
        } label: {
            NuggetRow(nugget: nugget)
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if nugget.isActive {
                Button {
                    moveAfterSwipeCloses(nugget, to: .paused)
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .tint(.gray)
            } else {
                Button {
                    moveAfterSwipeCloses(nugget, to: .active)
                } label: {
                    Label("Activate", systemImage: "play.circle")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not .destructive: the row stays until the deletion is confirmed.
            Button {
                pendingDelete = nugget
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .accessibilityAction(named: nugget.isActive ? "Pause" : "Activate") {
            move(nugget, to: nugget.isActive ? .paused : .active)
        }
        .accessibilityAction(named: "Delete") {
            pendingDelete = nugget
        }
    }
}

// MARK: Moving between sections

extension NuggetListView {
    /// About how long a swipe action takes to slide closed. Moving the row while
    /// it's still sliding back makes it shrink away half-open; waiting lets the
    /// swipe finish, then the row moves in one animation.
    static let swipeCloseDelay: Duration = .milliseconds(300)

    private func moveAfterSwipeCloses(_ nugget: Nugget, to state: NuggetState) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.swipeCloseDelay)
            move(nugget, to: state)
        }
    }

    /// A drag ended: map the flat drop offset back to a section and position.
    /// The row is already where it was dropped, so this doesn't animate; a
    /// refused drop puts it back and explains why.
    private func drop(_ source: IndexSet, at destination: Int, in layout: NuggetListLayout) {
        guard let from = source.first,
              let target = layout.destination(movingRowAt: from, toOffset: destination),
              case .nugget(let id, _) = layout.rows[from],
              let nugget = model.nugget(id: id) else { return }
        move(nugget, to: target.state, at: target.index, animated: false)
    }

    /// Moves the nugget and confirms a change of section with Undo, or explains
    /// why Active can't take it. Reordering within a section isn't confirmed.
    /// Used by the swipe, drag and accessibility actions.
    private func move(_ nugget: Nugget, to state: NuggetState, at index: Int? = nil, animated: Bool = true) {
        let result = withAnimation(animated ? .snappy : nil) { model.move(nugget, to: state, at: index) }
        switch result {
        case .moved(let move):
            toasts?.show(move.message, successHaptic: move.entersActive) { [model] in
                Self.undo(move, model: model, onRefused: { limitMessage = $0 })
            }
        case .activeFull(let message):
            limitMessage = message
        case .reordered, .unchanged, .failed:
            break
        }
    }

    /// Undo for a move, wherever it was made (the list or the editor).
    @MainActor
    static func undo(_ move: AppModel.StateMove, model: AppModel, onRefused: (String) -> Void) {
        if let message = withAnimation(.snappy, { model.undo(move) }) {
            onRefused(message)
        }
    }

    /// Short single-line preview of a nugget's text for the delete alert, in quotes.
    static func deletePreview(_ text: String, limit: Int = 80) -> String {
        let flat = NuggetText.stored(text).split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return NuggetText.quoted(flat) }
        return NuggetText.quoted(String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…")
    }
}

/// A row that reads as a section header: "Active  8 of 21", "Queued", "Paused".
private struct SectionHeaderRow: View {
    let state: NuggetState
    let activeCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.title)
            Spacer()
            if state == .active {
                Text("\(activeCount) of \(NuggetRules.activeLimit)")
                    .monospacedDigit()
            }
        }
        .font(.headline)
        .foregroundStyle(.secondary)
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 22, leading: 16, bottom: 6, trailing: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct NuggetRow: View {
    let nugget: Nugget

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nugget.quotedText)
                .font(.body)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let attribution = nugget.attribution {
                Text(attribution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits the nugget.")
    }
}

#Preview {
    NuggetListView()
        .environment(PreviewSupport.model())
        .environment(ToastCenter())
}
