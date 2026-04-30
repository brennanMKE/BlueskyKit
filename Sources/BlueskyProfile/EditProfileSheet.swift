import SwiftUI
import BlueskyCore
import BlueskyKit

public struct EditProfileSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var description: String
    @State private var isSaving = false

    private let onSave: (String, String) -> Void

    public init(displayName: String, description: String, onSave: @escaping (String, String) -> Void) {
        _displayName = State(initialValue: displayName)
        _description = State(initialValue: description)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display name", text: $displayName)
                }
                Section("Bio") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        onSave(displayName, description)
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("EditProfileSheet — Light") {
    EditProfileSheet(
        displayName: "Alice",
        description: "Building the open social web. 🦋",
        onSave: { _, _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("EditProfileSheet — Dark") {
    EditProfileSheet(
        displayName: "Alice",
        description: "Building the open social web. 🦋",
        onSave: { _, _ in }
    )
    .preferredColorScheme(.dark)
}
