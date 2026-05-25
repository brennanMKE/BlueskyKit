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

/// Moderation hub.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Moderation/index.tsx`. RN groups
/// the rows into three labeled sections — **Moderation tools**, **Content
/// filters**, and **Advanced** — and we keep the same order so users moving
/// between platforms find rows where they expect.
///
/// - **Moderation tools**: Interaction settings → Muted words & tags →
///   Moderation lists → Muted accounts → Blocked accounts → Verification
///   settings.
/// - **Content filters**: Adult content toggle → "Configure content filters"
///   (per-label preferences live on the dedicated screen so the hub stays
///   scannable).
/// - **Advanced**: Subscribed labelers list (each row → `LabelerProfileScreen`)
///   plus a destructive "Remove unavailable" cleanup action when any of the
///   subscribed DIDs failed to resolve via `app.bsky.labeler.getServices`.
///
/// Interaction settings navigates to `PostInteractionSettingsScreen` (#0138),
/// which writes the user's default `app.bsky.actor.defs#postInteractionSettingsPref`
/// (reply / quote defaults). Verification settings is still a placeholder
/// sheet pointing at bsky.app until a dedicated screen ships.
public struct ModerationScreen: View {
    private let network: any NetworkClient
    private let accountStore: any AccountStore

    @State private var viewModel: ModerationViewModel
    @State private var showVerificationSettingsPlaceholder = false

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            moderationToolsSection
            contentFiltersSection
            advancedSection
        }
        // UI-test coupling surface (#0183): `children: .contain` exposes the
        // List as one queryable element carrying `moderation-screen` while
        // keeping each row individually addressable by its own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moderation-screen")
        .navigationTitle("Moderation")
        .task {
            await viewModel.loadPreferences()
            await viewModel.loadSubscribedLabelers()
        }
        .refreshable {
            await viewModel.loadPreferences()
            await viewModel.loadSubscribedLabelers()
        }
        .sheet(isPresented: $showVerificationSettingsPlaceholder) {
            placeholderSheet(
                title: "Verification Settings",
                message: "Verification controls aren't yet available in the SwiftUI client. Manage them on bsky.app.",
                isPresented: $showVerificationSettingsPlaceholder
            )
        }
    }

    // MARK: - Moderation tools (Section 1)

    private var moderationToolsSection: some View {
        Section {
            NavigationLink {
                PostInteractionSettingsScreen(network: network)
            } label: {
                Label("Interaction settings", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("moderation-interaction-row")

            NavigationLink {
                MutedWordsScreen(network: network)
            } label: {
                Label("Muted words & tags", systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier("moderation-muted-words-row")

            NavigationLink {
                ModerationListsScreen(network: network, accountStore: accountStore)
            } label: {
                Label("Moderation lists", systemImage: "person.3")
            }
            .accessibilityIdentifier("moderation-lists-row")

            NavigationLink {
                MutesScreen(network: network, accountStore: accountStore)
            } label: {
                Label("Muted accounts", systemImage: "speaker.slash")
            }
            .accessibilityIdentifier("moderation-mutes-row")

            NavigationLink {
                BlocksScreen(network: network, accountStore: accountStore)
            } label: {
                Label("Blocked accounts", systemImage: "nosign")
            }
            .accessibilityIdentifier("moderation-blocks-row")

            Button {
                showVerificationSettingsPlaceholder = true
            } label: {
                hubRow(
                    title: "Verification settings",
                    systemImage: "checkmark.seal",
                    chevron: true
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Moderation tools")
        }
    }

    // MARK: - Content filters (Section 2)

    private var contentFiltersSection: some View {
        Section {
            // Adult-content toggle. RN gates this behind age-assurance; the
            // SwiftUI client doesn't model AA yet so the toggle is always
            // visible. Per-label visibility lives on the dedicated content
            // filter screen so this row stays scannable.
            Toggle(isOn: Binding(
                get: { viewModel.adultContentEnabled },
                set: { newValue in
                    Task { await viewModel.setAdultContent(enabled: newValue) }
                }
            )) {
                Label("Enable adult content", systemImage: "exclamationmark.shield")
            }

            NavigationLink {
                ContentFilterSettingsScreen(network: network, accountStore: accountStore)
            } label: {
                Label("Configure content filters", systemImage: "eye.slash")
            }
            .accessibilityIdentifier("moderation-content-filters-row")
        } header: {
            Text("Content filters")
        }
    }

    // MARK: - Advanced (Section 3)

    private var advancedSection: some View {
        Section {
            if !viewModel.unavailableLabelerDIDs.isEmpty {
                Button(role: .destructive) {
                    Task { await viewModel.removeUnavailableLabelers() }
                } label: {
                    Label("Remove unavailable", systemImage: "trash")
                }
            }

            if viewModel.isLoadingLabelers && viewModel.subscribedLabelers.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading labelers…")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.subscribedLabelerDIDs.isEmpty {
                Text("No subscribed labelers")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.subscribedLabelers, id: \.creator.did) { labeler in
                    NavigationLink {
                        LabelerProfileScreen(
                            labelerDID: labeler.creator.did.rawValue,
                            network: network
                        )
                    } label: {
                        labelerRow(for: labeler, isUnavailable: false)
                    }
                }

                // Surface DIDs the appview couldn't resolve so users can see
                // *what* the cleanup action is going to remove.
                ForEach(viewModel.unavailableLabelerDIDs, id: \.rawValue) { did in
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(did.rawValue)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Unavailable")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Subscribed labelers provide additional moderation labels on posts and accounts.")
        }
    }

    // MARK: - Row helpers

    private func hubRow(title: String, systemImage: String, chevron: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func labelerRow(for labeler: LabelerView, isUnavailable: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                url: labeler.creator.avatar,
                handle: labeler.creator.handle.rawValue,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(labeler.creator.displayName?.isEmpty == false
                     ? (labeler.creator.displayName ?? labeler.creator.handle.rawValue)
                     : labeler.creator.handle.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(labeler.creator.handle.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isUnavailable {
                Spacer()
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func placeholderSheet(
        title: String,
        message: String,
        isPresented: Binding<Bool>
    ) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Link("Open bsky.app", destination: URL(string: "https://bsky.app/")!)
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented.wrappedValue = false }
                }
            }
        }
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
