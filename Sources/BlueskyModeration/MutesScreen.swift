import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct MutesScreen: View {
    @State private var viewModel: ModerationViewModel

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if viewModel.mutes.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Muted Accounts",
                    systemImage: "speaker.slash",
                    description: Text("Accounts you mute will appear here.")
                )
            } else {
                ForEach(viewModel.mutes, id: \.did) { profile in
                    ActorRow(profile: profile) {
                        Task { await viewModel.unmute(did: profile.did) }
                    }
                    .onAppear {
                        if profile.did == viewModel.mutes.last?.did {
                            Task { await viewModel.loadMoreMutes() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Muted Accounts")
        .refreshable { await viewModel.loadMutes() }
        .task { await viewModel.loadMutes() }
        .overlay {
            if viewModel.isLoading && viewModel.mutes.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - ActorRow

private struct ActorRow: View {
    let profile: ProfileView
    let onUnmute: () -> Void

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

            Button("Unmute", role: .destructive) { onUnmute() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
