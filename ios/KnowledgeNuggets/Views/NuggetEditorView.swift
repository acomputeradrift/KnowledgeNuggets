import SwiftUI

struct NuggetEditorView: View {
    let nugget: Nugget?

    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastNuggetKind") private var lastKind = NuggetKind.default.rawValue
    @State private var draft: NuggetDraft
    @State private var showsCategory: Bool
    /// What a new nugget's editor started from: empty, or the kind and source
    /// carried over by Add Another. Changes from it need confirming to discard.
    @State private var baseline: NuggetDraft
    /// Set after a new nugget is saved; shown in place of the form.
    @State private var celebration: SaveCelebration?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case content, by, from, category
    }

    init(nugget: Nugget?) {
        self.nugget = nugget
        let draft = nugget.map(NuggetDraft.init) ?? NuggetDraft()
        _draft = State(initialValue: draft)
        _baseline = State(initialValue: draft)
        _showsCategory = State(initialValue: !draft.category.isEmpty)
    }

    private var original: NuggetDraft {
        if let nugget { return NuggetDraft(nugget) }
        var original = baseline
        original.kind = draft.kind
        return original
    }

    var body: some View {
        ZStack {
            if let celebration {
                SaveCelebrationView(
                    celebration: celebration,
                    onAddAnother: addAnother,
                    onGoToNuggets: goToNuggets,
                    onDone: { dismiss() }
                )
                    .transition(.opacity)
            } else {
                editor
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: celebration)
    }

    private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    KindPicker(selection: $draft.kind)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("Content") {
                    TextField("Type or paste…", text: $draft.text, axis: .vertical)
                        .lineLimit(4...14)
                        .focused($focus, equals: .content)
                        .accessibilityLabel("Content")
                }

                if draft.kind.hasSource {
                    sourceSection
                }

                activeSection
                categorySection
            }
            .listSectionSpacing(.compact)
            .animation(.default, value: draft.kind)
            .navigationTitle(nugget == nil ? "New Nugget" : "Edit Nugget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(!draft.canSave)
                }
            }
            .interactiveDismissDisabled(draft != original)
            .onAppear {
                if nugget == nil {
                    draft.kind = NuggetKind(rawValue: lastKind) ?? .default
                    focus = .content
                }
            }
        }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            // Above the fields so the keyboard never covers it.
            let recents = model.recentSources(for: draft.kind, matching: draft.book)
            if !recents.isEmpty {
                RecentSourcesRow(sources: recents) { source in
                    draft.book = source.from
                    if NuggetDraft.clean(draft.author) == nil, let by = source.by {
                        draft.author = by
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
            LabeledContent("By") {
                TextField("By", text: $draft.author, prompt: Text(draft.kind.byPrompt))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focus, equals: .by)
                    .onSubmit { focus = .from }
            }
            LabeledContent("From") {
                TextField("From", text: $draft.book, prompt: Text(draft.kind.fromPrompt))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .from)
                    .onSubmit(save)
            }

        } footer: {
            if let missing = draft.missingRequirement, draft.isValid {
                Text(missing)
            } else if draft.kind.supportsLookup {
                Text("Enter just the author or just the book and the other is filled in from Open Library when there's an exact match.")
            }
        }
    }

    /// Whether this nugget can be active: fewer than the limit are, or it already is.
    private var canBeActive: Bool {
        nugget?.isActive == true || model.active.count < NuggetRules.activeLimit
    }

    private var activeSection: some View {
        Section {
            // Shown off while the limit is reached, but the wish is kept: a new nugget
            // saved then still counts as kept inactive because the limit was reached.
            Toggle(isOn: Binding(
                get: { draft.isActive && canBeActive },
                set: { draft.isActive = $0 }
            )) {
                // A disabled Toggle in a Form keeps its label in the primary color.
                Text("Active")
                    .foregroundStyle(canBeActive ? .primary : .secondary)
            }
            .disabled(!canBeActive)
        } footer: {
            if !canBeActive {
                Text(NuggetRules.activeLimitReachedNote)
            }
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        if showsCategory {
            Section("Category") {
                TextField("Category", text: $draft.category, prompt: Text("Optional"))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .category)
                    .onSubmit(save)
            }
        } else {
            Section {
                Button {
                    showsCategory = true
                    focus = .category
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                }
            }
        }
    }

    private func save() {
        guard draft.canSave else { return }
        if let nugget {
            // Edits close, then confirm once the sheet is out of the way.
            let result = model.update(nugget, with: draft)
            dismiss()
            if let result { confirmAfterDismissal(result) }
            return
        }
        lastKind = draft.kind.rawValue
        // Saves that fail close as before. New nuggets celebrate.
        guard let result = model.save(draft) else {
            dismiss()
            return
        }
        focus = nil
        celebration = result
    }

    /// Shows the edit's confirmation after the sheet has slid away. A flipped
    /// Active switch confirms the move, with Undo, like the list's swipe.
    private func confirmAfterDismissal(_ result: AppModel.EditResult) {
        guard let toasts else { return }
        let model = self.model
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            switch result {
            case .updated:
                toasts.show("Nugget updated")
            case .moved(let move):
                toasts.show(move.message, successHaptic: move.isActive) {
                    NuggetListView.undo(move, model: model, onRefused: { model.errorMessage = $0 })
                }
            }
        }
    }

    /// Closes the sheet and shows the Nuggets tab, where the new inactive
    /// nugget can be swiped to Active once a spot is free.
    private func goToNuggets() {
        dismiss()
        model.selectedTab = .nuggets
    }

    /// Back to a fresh form that keeps the kind and source, so several nuggets
    /// from one book are quick to add.
    private func addAnother() {
        // Keeps the Active switch too; it shows off by itself if the rotation filled up.
        let next = NuggetDraft(author: draft.author, book: draft.book, kind: draft.kind, isActive: draft.isActive)
        draft = next
        baseline = next
        showsCategory = false
        celebration = nil
        // Focus once the form has faded back in; focus set mid-transition is dropped.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            focus = .content
        }
    }
}

/// One tap to choose the kind of nugget.
struct KindPicker: View {
    @Binding var selection: NuggetKind

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NuggetKind.allCases) { kind in
                        chip(for: kind).id(kind)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind")
    }

    @ViewBuilder
    private func chip(for kind: NuggetKind) -> some View {
        let isSelected = kind == selection
        let button = Button {
            selection = kind
        } label: {
            Label(kind.title, systemImage: kind.symbol)
                .font(.subheadline.weight(.medium))
        }
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if isSelected {
            button.primaryActionStyle()
        } else {
            button.buttonStyle(.bordered).tint(.secondary)
        }
    }
}

/// Recently used sources, tap to fill From (and By, if it's empty).
struct RecentSourcesRow: View {
    let sources: [AppModel.RecentSource]
    let onSelect: (AppModel.RecentSource) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Recent")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(sources) { source in
                    Button(source.from) { onSelect(source) }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Fills in From\(source.by.map { " and By with \($0)" } ?? "").")
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview("New") {
    NuggetEditorView(nugget: nil)
        .environment(PreviewSupport.model())
        .environment(ToastCenter())
}
