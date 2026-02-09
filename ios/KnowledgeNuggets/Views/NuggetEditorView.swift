import SwiftUI

struct NuggetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var authorName: String
    @State private var bookTitle: String
    @State private var category: String
    private let existing: Nugget?
    let onSave: (Nugget) -> Void

    init(existing: Nugget? = nil, onSave: @escaping (Nugget) -> Void) {
        self.existing = existing
        _text = State(initialValue: existing?.text ?? "")
        _authorName = State(initialValue: existing?.authorName ?? "")
        _bookTitle = State(initialValue: existing?.bookTitle ?? "")
        _category = State(initialValue: existing?.category ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Content")) {
                    TextEditor(text: $text)
                        .frame(height: 120)
                }
                Section(header: Text("Author")) {
                    TextField("Author name", text: $authorName)
                }
                Section(header: Text("Book")) {
                    TextField("Book title", text: $bookTitle)
                }
                Section(header: Text("Category")) {
                    TextField("Category", text: $category)
                }
                Section(header: Text("Amazon")) {
                    if let link = existing?.amazonLink, let url = URL(string: link) {
                        Link("View on Amazon", destination: url)
                    } else {
                        Text("Auto-generated after save")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Nugget" : "Edit Nugget")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let nugget = Nugget(
                            id: existing?.id ?? UUID().uuidString,
                            text: text,
                            authorName: authorName.isEmpty ? nil : authorName,
                            bookTitle: bookTitle.isEmpty ? nil : bookTitle,
                            amazonLink: existing?.amazonLink,
                            category: category.isEmpty ? nil : category,
                            position: existing?.position,
                            active: existing?.active ?? true
                        )
                        onSave(nugget)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
