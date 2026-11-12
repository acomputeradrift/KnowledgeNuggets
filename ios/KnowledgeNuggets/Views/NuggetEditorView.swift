import SwiftUI

struct NuggetEditorView: View {
    let nugget: Nugget?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NuggetDraft
    @State private var limitMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case text, author, book, category
    }

    init(nugget: Nugget?) {
        self.nugget = nugget
        _draft = State(initialValue: nugget.map(NuggetDraft.init) ?? NuggetDraft())
    }

    private var original: NuggetDraft {
        nugget.map(NuggetDraft.init) ?? NuggetDraft()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type or paste the passage", text: $draft.text, axis: .vertical)
                        .lineLimit(4...14)
                        .focused($focus, equals: .text)
                        .accessibilityLabel("Passage")
                } header: {
                    Text("Passage")
                }

                Section {
                    TextField("Author", text: $draft.author)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .author)
                        .onSubmit { focus = .book }
                    TextField("Book", text: $draft.book)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .book)
                        .onSubmit { focus = .category }
                } header: {
                    Text("Source")
                } footer: {
                    Text("Optional. Enter just the author or just the book and the other is filled in from Open Library when there's an exact match.")
                }

                Section {
                    TextField("Category", text: $draft.category)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .category)
                        .onSubmit(save)
                } header: {
                    Text("Category")
                } footer: {
                    Text("Optional.")
                }
            }
            .navigationTitle(nugget == nil ? "New Nugget" : "Edit Nugget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(!draft.isValid)
                }
            }
            .interactiveDismissDisabled(draft != original)
            .onAppear {
                if nugget == nil { focus = .text }
            }
            .alert(
                "Saved as Inactive",
                isPresented: Binding(
                    get: { limitMessage != nil },
                    set: { if !$0 { limitMessage = nil } }
                ),
                actions: { Button("OK") { dismiss() } },
                message: { Text(limitMessage ?? "") }
            )
        }
    }

    private func save() {
        guard draft.isValid else { return }
        if let message = model.save(draft, editing: nugget) {
            limitMessage = message
        } else {
            dismiss()
        }
    }
}

#Preview("New") {
    NuggetEditorView(nugget: nil)
        .environment(PreviewSupport.model())
}
