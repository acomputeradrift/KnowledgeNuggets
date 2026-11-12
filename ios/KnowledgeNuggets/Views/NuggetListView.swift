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
            .confirmationDialog(
                "Delete this nugget?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { nugget in
                Button("Delete Nugget", role: .destructive) {
                    withAnimation { model.delete(nugget) }
                }
            } message: { _ in
                Text("This can't be undone.")
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
                    ForEach(model.active) { nugget in
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
                    ForEach(model.inactive) { nugget in
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
                    withAnimation { _ = model.setActive(nugget, false) }
                } label: {
                    Label("Deactivate", systemImage: "pause.circle")
                }
                .tint(.gray)
            } else {
                Button {
                    withAnimation { limitMessage = model.setActive(nugget, true) }
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
            if nugget.isActive {
                _ = model.setActive(nugget, false)
            } else {
                limitMessage = model.setActive(nugget, true)
            }
        }
        .accessibilityAction(named: "Delete") {
            pendingDelete = nugget
        }
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
}
