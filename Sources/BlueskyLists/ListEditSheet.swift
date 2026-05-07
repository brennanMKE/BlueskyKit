import SwiftUI
import BlueskyCore
import BlueskyKit

/// Edit-mode mirror of `ListCreateSheet`. Pre-populates name and description
/// from an existing `ListView` and writes via `com.atproto.repo.putRecord`
/// through `ListDetailViewModel.editList`. Avatar editing is intentionally
/// deferred — see Gotchas in #0127. Purpose is shown read-only because the
/// list lexicon does not allow changing purpose after creation.
struct ListEditSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var isSaving = false

    private let purpose: String
    private let onSave: (String, String?) -> Void

    /// - Parameters:
    ///   - list: The existing list to edit; supplies pre-fill values.
    ///   - onSave: Called with the trimmed name and optional description on
    ///     Save tap. The caller is responsible for actually performing the
    ///     network write and dismissing.
    init(list: ListView, onSave: @escaping (String, String?) -> Void) {
        _name = State(initialValue: list.name)
        _description = State(initialValue: list.description ?? "")
        self.purpose = list.purpose
        self.onSave = onSave
    }

    private var isCurate: Bool { purpose == "app.bsky.graph.defs#curatelist" }
    private var purposeLabel: String { isCurate ? "Curated List" : "Moderation List" }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("List Name") {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textContentType(.name)
                        #endif
                }

                Section("Type") {
                    // Purpose is fixed at creation time on the AT Proto side;
                    // RN's edit dialog also shows it as immutable.
                    HStack {
                        Text(purposeLabel)
                        Spacer()
                        Text("Cannot be changed").foregroundStyle(.secondary).font(.caption)
                    }
                }

                Section("Description (optional)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isCurate ? "Edit user list" : "Edit moderation list")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        isSaving = true
                        onSave(trimmedName, trimmedDescription.isEmpty ? nil : trimmedDescription)
                        dismiss()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }
}

// MARK: - Previews

private let _previewList = ListView(
    uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.list/abc"),
    cid: "bafy",
    creator: ProfileView(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice",
        description: nil,
        avatar: nil,
        labels: [],
        indexedAt: nil,
        viewer: nil
    ),
    name: "Great Posters",
    purpose: "app.bsky.graph.defs#curatelist",
    description: "The posters who never miss.",
    avatar: nil,
    labels: [],
    indexedAt: nil
)

#Preview("ListEditSheet — Light") {
    ListEditSheet(list: _previewList) { _, _ in }
        .preferredColorScheme(.light)
}

#Preview("ListEditSheet — Dark") {
    ListEditSheet(list: _previewList) { _, _ in }
        .preferredColorScheme(.dark)
}
