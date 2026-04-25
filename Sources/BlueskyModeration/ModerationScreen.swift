import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

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
