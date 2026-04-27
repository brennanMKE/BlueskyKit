import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

struct AppPasswordsScreen: View {
    @State private var viewModel: AppPasswordsViewModel
    @State private var isShowingCreate = false
    @State private var newName = ""

    init(network: any NetworkClient) {
        _viewModel = State(initialValue: AppPasswordsViewModel(network: network))
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.passwords.isEmpty {
                ContentUnavailableView(
                    "No App Passwords",
                    systemImage: "key.slash",
                    description: Text("App passwords let third-party apps access your account without your main password.")
                )
            } else {
                ForEach(viewModel.passwords, id: \.name) { pw in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pw.name).fontWeight(.medium)
                        Text("Created \(pw.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.revoke(name: pw.name) }
                        } label: {
                            Label("Revoke", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("App Passwords")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingCreate) {
            createSheet
        }
        .alert("App Password Created", isPresented: Binding(
            get: { viewModel.newPassword != nil },
            set: { if !$0 { viewModel.clearNewPassword() } }
        )) {
            Button("Copy") {
                if let pw = viewModel.newPassword {
                    #if os(iOS)
                    UIPasteboard.general.string = pw
                    #else
                    NSPasteboard.general.setString(pw, forType: .string)
                    #endif
                    viewModel.clearNewPassword()
                }
            }
            Button("OK", role: .cancel) { viewModel.clearNewPassword() }
        } message: {
            if let pw = viewModel.newPassword {
                Text("Save this password — it won't be shown again.\n\n\(pw)")
            }
        }
        .task { await viewModel.load() }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Password Name"),
                    footer: Text("Use a name that identifies the app or service.")
                ) {
                    TextField("e.g. My RSS Reader", text: $newName)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add App Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingCreate = false
                        newName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newName
                        isShowingCreate = false
                        newName = ""
                        Task { await viewModel.create(name: name) }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCreating)
                }
            }
        }
    }
}
