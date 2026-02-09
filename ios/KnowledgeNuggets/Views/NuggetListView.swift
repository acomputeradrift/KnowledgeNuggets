import SwiftUI

struct NuggetListView: View {
    @State private var nuggets: [Nugget] = []
    @State private var showingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
                ForEach(nuggets) { nugget in
                    NavigationLink {
                        NuggetEditorView(existing: nugget, onSave: { updated in
                            Task {
                                do {
                                    let saved = try await APIClient.shared.updateNugget(updated, original: nugget)
                                    if let index = nuggets.firstIndex(where: { $0.id == saved.id }) {
                                        nuggets[index] = saved
                                    }
                                } catch {
                                    errorMessage = "Failed to update nugget."
                                }
                            }
                        })
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(nugget.text)
                                .font(.headline)
                            if let author = nugget.authorName {
                                Text(author).font(.subheadline).foregroundColor(.secondary)
                            }
                            if let book = nugget.bookTitle {
                                Text(book).font(.subheadline).foregroundColor(.secondary)
                            }
                            if let category = nugget.category {
                                Text(category).font(.caption).foregroundColor(.secondary)
                            }
                            if let link = nugget.amazonLink, let url = URL(string: link) {
                                Link("View on Amazon", destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Knowledge Nuggets")
            .toolbar {
                Button("Add") { showingEditor = true }
            }
            .sheet(isPresented: $showingEditor) {
                NuggetEditorView(onSave: { newNugget in
                    Task {
                        do {
                            let saved = try await APIClient.shared.createNugget(newNugget)
                            nuggets.append(saved)
                        } catch {
                            errorMessage = "Failed to save nugget."
                        }
                    }
                })
            }
        }
        .task {
            do {
                nuggets = try await APIClient.shared.fetchNuggets()
            } catch {
                errorMessage = "Failed to load nuggets."
            }
        }
    }
}
