import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

struct StarterPackCreateSheet: View {

    @State private var name = ""
    @State private var description = ""
    @State private var selectedList: ListView?
    @State private var showListPicker = false
    @State private var viewModel: ListsViewModel
    @Environment(\.dismiss) private var dismiss

    let onDismiss: () -> Void

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ListsViewModel(network: network, accountStore: accountStore))
        self.onDismiss = onDismiss
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedList != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Starter Pack Name") {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textContentType(.name)
                        #endif
                }

                Section("Description (optional)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }

                Section("Member List") {
                    if let list = selectedList {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.headline)
                                Text("@\(list.creator.handle.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showListPicker = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Button("Select a List") {
                            showListPicker = true
                        }
                    }
                }
            }
            .navigationTitle("New Starter Pack")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createStarterPack() }
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showListPicker) {
                listPickerSheet
            }
        }
    }

    // MARK: - List picker

    private var listPickerSheet: some View {
        NavigationStack {
            ListPickerView(viewModel: viewModel) { list in
                selectedList = list
                showListPicker = false
            }
            .navigationTitle("Select List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showListPicker = false }
                }
            }
        }
    }

    // MARK: - Create

    private func createStarterPack() async {
        guard let list = selectedList else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel.createStarterPack(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            listURI: list.uri
        )
        dismiss()
        onDismiss()
    }
}

// MARK: - ListPickerView

private struct ListPickerView: View {
    @Bindable var viewModel: ListsViewModel
    let onSelect: (ListView) -> Void

    var body: some View {
        List(viewModel.lists, id: \.uri) { list in
            Button {
                onSelect(list)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: list.avatar, handle: list.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name).font(.headline).lineLimit(1)
                        Text("@\(list.creator.handle.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if viewModel.isLoading && viewModel.lists.isEmpty {
                ProgressView()
            }
        }
        .task {
            if let did = try? await viewModel.currentDID() {
                await viewModel.loadLists(actorDID: did)
            }
        }
    }
}
