import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

public struct ModerationScreen: View {
    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    MutesScreen(network: network, accountStore: accountStore)
                } label: {
                    Label("Muted Accounts", systemImage: "speaker.slash")
                }

                NavigationLink {
                    BlocksScreen(network: network, accountStore: accountStore)
                } label: {
                    Label("Blocked Accounts", systemImage: "nosign")
                }

                NavigationLink {
                    ModerationListsScreen(network: network, accountStore: accountStore)
                } label: {
                    Label("Moderation Lists", systemImage: "list.bullet.clipboard")
                }
            } header: {
                Text("Account Actions")
            }

            Section {
                NavigationLink {
                    ContentFilterSettingsScreen(network: network, accountStore: accountStore)
                } label: {
                    Label("Content Filters", systemImage: "eye.slash")
                }
            } header: {
                Text("Content")
            }
        }
        .navigationTitle("Moderation")
    }
}

// MARK: - Previews

#Preview("ModerationScreen — Light") {
    NavigationStack {
        ModerationScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ModerationScreen — Dark") {
    NavigationStack {
        ModerationScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
