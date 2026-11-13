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
                if model.active.count > 1 {
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

    private var list: some View {
        List {
            Section {
                if model.active.isEmpty {
                    Text("No active nuggets. Swipe right on an inactive one to add it to the rotation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.active, id: \.activeRowID) { nugget in
                        row(for: nugget)
                    }
                    .onMove { source, destination in
                        model.moveActive(fromOffsets: source, toOffset: destination)
                    }
                }
            } header: {
                Text("Active")
            } footer: {
                Text("\(model.active.count) of \(NuggetRules.activeLimit) in the daily rotation, shown in the order they arrive. Touch and hold to reorder.")
            }

            if !model.inactive.isEmpty {
                Section("Inactive") {
                    ForEach(model.inactive, id: \.inactiveRowID) { nugget in
                        row(for: nugget)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for nugget: Nugget) -> some View {
        Button {
            editor = .edit(nugget)
        } label: {
            NuggetRow(nugget: nugget)
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if nugget.isActive {
                Button {
                    moveAfterSwipeCloses(nugget, toActive: false)
                } label: {
                    Label("Deactivate", systemImage: "pause.circle")
                }
                .tint(.gray)
            } else {
                Button {
                    moveAfterSwipeCloses(nugget, toActive: true)
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
        .accessibilityAction(named: nugget.isActive ? "Deactivate" : "Activate") {
            move(nugget, toActive: !nugget.isActive)
        }
        .accessibilityAction(named: "Delete") {
            pendingDelete = nugget
        }
    }
}

// MARK: Moving between Active and Inactive

private extension Nugget {
    /// Row ids that differ by section, so a move between sections is a plain
    /// remove here and insert there rather than a cross-section move.
    var activeRowID: String { "active-\(id.uuidString)" }
    var inactiveRowID: String { "inactive-\(id.uuidString)" }
}

extension NuggetListView {
    /// About how long a swipe action takes to slide closed. Moving the row while
    /// it's still sliding back makes it shrink away half-open; waiting lets the
    /// swipe finish, then the row leaves in one animation. (The row ids above
    /// stop the other glitch: the row flying up off the top and back.)
    static let swipeCloseDelay: Duration = .milliseconds(300)

    private func moveAfterSwipeCloses(_ nugget: Nugget, toActive isActive: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.swipeCloseDelay)
            move(nugget, toActive: isActive)
        }
    }

    /// Moves the nugget with one animation and confirms it, or explains why the
    /// rotation can't take it. Used by the swipe and accessibility actions.
    private func move(_ nugget: Nugget, toActive isActive: Bool) {
        let result = withAnimation(.snappy) { model.move(nugget, toActive: isActive) }
        switch result {
        case .moved(let move):
            toasts?.show(move.message, successHaptic: move.isActive) { [model] in
                Self.undo(move, model: model, onRefused: { limitMessage = $0 })
            }
        case .rotationFull(let message):
            limitMessage = message
        case .unchanged, .failed:
            break
        }
    }

    /// Undo for a move, wherever it was made (the list or the editor).
    @MainActor
    static func undo(_ move: AppModel.ActiveMove, model: AppModel, onRefused: (String) -> Void) {
        if let message = withAnimation(.snappy, { model.undo(move) }) {
            onRefused(message)
        }
    }
    /// Short single-line preview of a nugget's text for the delete alert.
    static func deletePreview(_ text: String, limit: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

struct NuggetRow: View {
    let nugget: Nugget

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nugget.text)
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
