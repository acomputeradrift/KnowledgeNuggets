import SwiftUI

/// A single nugget in full, opened from Today or from a notification.
struct NuggetDetailView: View {
    let nuggetID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            Group {
                if let nugget = model.nugget(id: nuggetID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(nugget.text)
                                .font(.title2)
                                .fontDesign(.serif)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                if let author = nugget.author {
                                    Text(author).font(.headline)
                                }
                                if let book = nugget.book {
                                    Text(book).font(.subheadline).italic().foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)

                            HStack(spacing: 8) {
                                Label(nugget.nuggetKind.title, systemImage: nugget.nuggetKind.symbol)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                                if let category = nugget.category {
                                    Text(category)
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                        .accessibilityLabel("Category: \(category)")
                                }
                                Text(nugget.isActive ? "· Active" : "· Inactive")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .sheet(isPresented: $isEditing) {
                        NuggetEditorView(nugget: nugget)
                    }
                } else {
                    ContentUnavailableView(
                        "Nugget Not Found",
                        systemImage: "questionmark.circle",
                        description: Text("It may have been deleted.")
                    )
                }
            }
            .navigationTitle("Nugget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if model.nugget(id: nuggetID) != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") { isEditing = true }
                    }
                }
            }
        }
    }
}
