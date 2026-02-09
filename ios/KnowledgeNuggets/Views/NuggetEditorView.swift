import SwiftUI

struct NuggetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var authorName: String = ""
    @State private var bookTitle: String = ""
    @State private var category: String = ""

    let onSave: (Nugget) -> Void

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
                    Text("Auto-generated after save")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Nugget")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let nugget = Nugget(
                            id: UUID().uuidString,
                            text: text,
                            authorName: authorName.isEmpty ? nil : authorName,
                            bookTitle: bookTitle.isEmpty ? nil : bookTitle,
                            amazonLink: nil,
                            category: category.isEmpty ? nil : category,
                            position: nil,
                            active: true
                        )
                        onSave(nugget)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
