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

public struct ListsScreen: View {

    @State private var viewModel: ListsViewModel
    @State private var showCreateSheet = false
    /// Resolved on first appear from `accountStore.loadCurrentDID()`. Drives
    /// owner-only edit / delete affordances inside `ListDetailScreen`; when
    /// the signed-in viewer is `nil` (logged out), edit/delete stays hidden.
    @State private var viewerDID: DID?
    private let actorDID: String
    private let network: any NetworkClient
    private let accountStore: any AccountStore
    /// Surfaces creator-tap from the list-detail header back to the host so it
    /// can push a `ProfileScreen`. Optional because `BlueskyLists` cannot
    /// import `BlueskyProfile`; the app shell wires the navigation.
    private let onProfileTap: ((DID) -> Void)?

    public init(
        actorDID: String,
        network: any NetworkClient,
        accountStore: any AccountStore,
        onProfileTap: ((DID) -> Void)? = nil
    ) {
        self.actorDID = actorDID
        self.network = network
        self.accountStore = accountStore
        self.onProfileTap = onProfileTap
        _viewModel = State(initialValue: ListsViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if viewModel.lists.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Lists",
                    systemImage: "list.bullet",
                    description: Text("Lists you create will appear here.")
                )
            } else {
                // "My Lists" — lists the viewer authored. Mirrors RN's
                // `MyLists filter="curate"` which only fetches lists where
                // `actor === currentAccount.did`. Owner-only edit / delete
                // affordances live inside `ListDetailScreen` (#0127).
                Section("My Lists") {
                    ownedSection
                }

                // "Subscribed" — lists the viewer has subscribed to without
                // owning. RN's curate hub doesn't surface these (they flow
                // through `getListMutes` for the `mod` filter only); kept
                // here as a placeholder so the section structure mirrors
                // mod-list parity expectations. Will be empty in the curate
                // hub by design — see #0131 notes.
                Section("Subscribed") {
                    subscribedSection
                }
            }
        }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            ListCreateSheet { name, purpose, description in
                Task {
                    await viewModel.createList(name: name, description: description, purpose: purpose)
                }
                showCreateSheet = false
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.lists.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.loadLists(actorDID: actorDID) }
        .task {
            // Resolve the signed-in viewer DID once so the detail screen
            // can surface owner-only edit/delete affordances and so the
            // hub can split owned vs subscribed lists. Swallow errors —
            // failure just means owner-only affordances stay hidden and
            // every list lands in "My Lists" (the historical flat view).
            await viewModel.resolveViewerDID()
            if viewerDID == nil {
                viewerDID = viewModel.viewerDID
            }
            await viewModel.loadLists(actorDID: actorDID)
        }
    }

    // MARK: - Sections

    /// Rows for lists the viewer authored. When logged out the view model
    /// falls back to returning the full list set so we never strand rows.
    @ViewBuilder
    private var ownedSection: some View {
        let owned = viewModel.ownedLists
        if owned.isEmpty {
            Text("Lists you create will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(owned, id: \.uri) { list in
                NavigationLink {
                    ListDetailScreen(
                        listURI: list.uri,
                        network: network,
                        accountStore: accountStore,
                        viewerDID: viewerDID,
                        onProfileTap: onProfileTap
                    )
                } label: {
                    ListRow(list: list)
                }
                .onAppear {
                    // Paginate against the underlying flat list so the
                    // tail-of-list trigger fires regardless of which
                    // section the last row landed in.
                    if list.uri == viewModel.lists.last?.uri {
                        Task { await viewModel.loadMore(actorDID: actorDID) }
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let list = owned[index]
                    Task { await viewModel.deleteList(uri: list.uri) }
                }
            }
        }
    }

    /// Rows for lists the viewer is subscribed to without owning. RN's
    /// curate hub doesn't fetch these — see `subscribedLists` on the
    /// view model — so the placeholder is the expected steady state.
    @ViewBuilder
    private var subscribedSection: some View {
        let subscribed = viewModel.subscribedLists
        if subscribed.isEmpty {
            Text("Subscribed lists will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(subscribed, id: \.uri) { list in
                NavigationLink {
                    ListDetailScreen(
                        listURI: list.uri,
                        network: network,
                        accountStore: accountStore,
                        viewerDID: viewerDID,
                        onProfileTap: onProfileTap
                    )
                } label: {
                    ListRow(list: list)
                }
            }
        }
    }
}

// MARK: - ListRow

private struct ListRow: View {
    let list: ListView

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: list.avatar, handle: list.name, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.headline)
                        .lineLimit(1)
                    PurposeBadge(purpose: list.purpose)
                }
                Text("by @\(list.creator.handle.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let desc = list.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PurposeBadge

private struct PurposeBadge: View {
    let purpose: String

    private var label: String {
        purpose == "app.bsky.graph.defs#modlist" ? "MOD" : "Curated"
    }

    private var color: Color {
        purpose == "app.bsky.graph.defs#modlist" ? .orange : .blue
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("ListsScreen — Light") {
    NavigationStack {
        ListsScreen(
            actorDID: "did:plc:alice",
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ListsScreen — Dark") {
    NavigationStack {
        ListsScreen(
            actorDID: "did:plc:alice",
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
