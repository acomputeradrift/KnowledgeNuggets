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
    /// The existing nugget opened from the duplicate footer's Show It.
    @State private var shownDuplicate: NuggetLink?
    /// Whether the user tapped the state pill. A new nugget left on the Queued
    /// default (Active was full) still counts as wanting Active, so the
    /// celebration explains the full rotation (layout B) rather than a choice (C).
    @State private var pickedState = false
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

                Section {
                    TextField("Type or paste…", text: $draft.text, axis: .vertical)
                        .lineLimit(4...14)
                        .focused($focus, equals: .content)
                        .accessibilityLabel("Content")
                } header: {
                    Text("Content")
                } footer: {
                    if let duplicate {
                        DuplicateNote {
                            shownDuplicate = NuggetLink(id: duplicate.id)
                        }
                    }
                }

                if draft.kind.hasSource {
                    sourceSection
                }

                stateSection
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
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(draft != original)
            .onAppear {
                if nugget == nil {
                    draft.kind = NuggetKind(rawValue: lastKind) ?? .default
                    // Active when there's room, Queued when it's full.
                    draft.state = model.defaultNewState
                    baseline.state = draft.state
                    focus = .content
                }
            }
            .sheet(item: $shownDuplicate) { link in
                NuggetDetailView(nuggetID: link.id)
            }
        }
    }

    /// The nugget that already has this content, other than the one being edited.
    private var duplicate: Nugget? {
        guard draft.isValid else { return nil }
        return model.duplicate(of: draft.text, excluding: nugget)
    }

    private var canSave: Bool { draft.canSave && duplicate == nil }

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

    /// Whether this nugget can be active: there's a free spot, or it already is.
    private var canBeActive: Bool { model.canBeActive(nugget) }

    private var stateSection: some View {
        Section {
            StatePicker(selection: Binding(
                get: { draft.state },
                set: { draft.state = $0; pickedState = true }
            ), activeEnabled: canBeActive)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        } footer: {
            Text(canBeActive ? NuggetRules.statePickerNote : NuggetRules.activeLimitReachedNote)
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
        guard canSave else { return }
        if let nugget {
            // Edits close, then confirm once the sheet is out of the way.
            let result = model.update(nugget, with: draft)
            dismiss()
            if let result { confirmAfterDismissal(result) }
            return
        }
        lastKind = draft.kind.rawValue
        var toSave = draft
        if !pickedState, toSave.state == .queued, !canBeActive { toSave.state = .active }
        // Saves that fail close as before. New nuggets celebrate.
        guard let result = model.save(toSave) else {
            dismiss()
            return
        }
        focus = nil
        celebration = result
    }

    /// Shows the edit's confirmation after the sheet has slid away. A changed
    /// section confirms the move, with Undo, like the list.
    private func confirmAfterDismissal(_ result: AppModel.EditResult) {
        guard let toasts else { return }
        let model = self.model
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            switch result {
            case .updated:
                toasts.show("Nugget updated")
            case .moved(let move):
                toasts.show(move.message, successHaptic: move.entersActive) {
                    NuggetListView.undo(move, model: model, onRefused: { model.errorMessage = $0 })
                }
            }
        }
    }

    /// Closes the sheet and shows the Nuggets tab, where the new queued
    /// nugget can be swiped to Activate once a spot is free.
    private func goToNuggets() {
        dismiss()
        model.selectedTab = .nuggets
    }

    /// Back to a fresh form that keeps the kind and source, so several nuggets
    /// from one book are quick to add.
    private func addAnother() {
        // Keeps the chosen section too, except Active once it has filled up.
        let state = draft.state == .active ? model.defaultNewState : draft.state
        let next = NuggetDraft(author: draft.author, book: draft.book, kind: draft.kind, state: state)
        draft = next
        baseline = next
        showsCategory = false
        pickedState = false
        celebration = nil
        // Focus once the form has faded back in; focus set mid-transition is dropped.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            focus = .content
        }
    }
}

/// "You already have this nugget." with a Show It button, under Content.
struct DuplicateNote: View {
    let onShow: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label("You already have this nugget.", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.secondary)
            Button("Show it", action: onShow)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityHint("Opens the nugget you already have.")
        }
        .padding(.top, 2)
    }
}

/// Active | Queued | Paused as a pill: a capsule track with the chosen segment
/// filled amber. Active can be greyed out when it's full.
struct StatePicker: View {
    @Binding var selection: NuggetState
    var activeEnabled = true

    @Namespace private var highlight
    @ScaledMetric(relativeTo: .subheadline) private var inset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NuggetState.allCases) { state in
                segment(for: state)
            }
        }
        .padding(inset)
        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
        .animation(.snappy(duration: 0.25), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section")
    }

    private func segment(for state: NuggetState) -> some View {
        let isSelected = state == selection
        let isEnabled = state != .active || activeEnabled
        return Button {
            selection = state
        } label: {
            Text(state.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary.opacity(0.6)))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color("AccentColor"))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isEnabled ? "" : NuggetRules.activeLimitReachedNote)
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
