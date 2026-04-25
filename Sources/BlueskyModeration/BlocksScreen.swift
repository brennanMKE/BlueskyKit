import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct BlocksScreen: View {
    @State private var viewModel: ModerationViewModel

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if viewModel.blocks.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Blocked Accounts",
                    systemImage: "nosign",
                    description: Text("Accounts you block will appear here.")
                )
            } else {
                ForEach(viewModel.blocks, id: \.did) { profile in
                    BlockedActorRow(profile: profile) {
                        Task { await viewModel.unblock(profile: profile) }
                    }
                    .onAppear {
                        if profile.did == viewModel.blocks.last?.did {
                            Task { await viewModel.loadMoreBlocks() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Blocked Accounts")
        .refreshable { await viewModel.loadBlocks() }
        .task { await viewModel.loadBlocks() }
        .overlay {
            if viewModel.isLoading && viewModel.blocks.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - BlockedActorRow

private struct BlockedActorRow: View {
    let profile: ProfileView
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: profile.avatar, handle: profile.handle.rawValue, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                if let name = profile.displayName, !name.isEmpty {
                    Text(name).font(.headline).lineLimit(1)
                }
                Text("@\(profile.handle.rawValue)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Button("Unblock", role: .destructive) { onUnblock() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
