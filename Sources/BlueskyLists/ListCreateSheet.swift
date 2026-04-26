import SwiftUI
import BlueskyCore

struct ListCreateSheet: View {

    @State private var name = ""
    @State private var purpose = "app.bsky.graph.defs#curatelist"
    @State private var description = ""
    @Environment(\.dismiss) private var dismiss

    let onCreate: (String, String, String?) -> Void

    public init(onCreate: @escaping (String, String, String?) -> Void) {
        self.onCreate = onCreate
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

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
                    Picker("Purpose", selection: $purpose) {
                        Text("Curated List").tag("app.bsky.graph.defs#curatelist")
                        Text("Moderation List").tag("app.bsky.graph.defs#modlist")
                    }
                    .pickerStyle(.menu)
                }

                Section("Description (optional)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("New List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            purpose,
                            trimmedDescription.isEmpty ? nil : trimmedDescription
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
