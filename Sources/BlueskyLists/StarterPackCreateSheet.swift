import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

struct StarterPackCreateSheet: View {

    @State private var name = ""
    @State private var description = ""
    @State private var selectedList: ListView?
    @State private var showListPicker = false
    @Environment(\.dismiss) private var dismiss

    let network: any NetworkClient
    let accountStore: any AccountStore
    let onDismiss: () -> Void

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        onDismiss: @escaping () -> Void
    ) {
        self.network = network
        self.accountStore = accountStore
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
            ListPickerView(
                network: network,
                accountStore: accountStore
            ) { list in
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
        guard let list = selectedList,
              let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = StarterPackRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            list: list.uri
        )
        let req = CreateRecordRequest(
            repo: viewerDID.rawValue,
            collection: "app.bsky.graph.starterpack",
            record: record
        )
        do {
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
            )
            dismiss()
            onDismiss()
        } catch {
            // Error silently — could surface via alert in a future iteration
        }
    }
}

// MARK: - ListPickerView

private struct ListPickerView: View {
    @State private var viewModel: ListsViewModel
    let onSelect: (ListView) -> Void

    init(network: any NetworkClient, accountStore: any AccountStore, onSelect: @escaping (ListView) -> Void) {
        _viewModel = State(initialValue: ListsViewModel(network: network, accountStore: accountStore))
        self.onSelect = onSelect
    }

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
