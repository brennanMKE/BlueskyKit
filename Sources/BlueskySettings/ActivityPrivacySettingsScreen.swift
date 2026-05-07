import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "ActivityPrivacySettings"
)

// MARK: - ActivityPrivacySettingsScreen

/// Activity Privacy settings screen — controls who is allowed to be notified
/// about the signed-in user's posts and replies. Mirrors RN's
/// `Bluesky-ReactNative/src/screens/Settings/ActivityPrivacySettings.tsx`.
///
/// Persistence is via `com.atproto.repo.{getRecord,putRecord}` against
/// `app.bsky.notification.declaration` at `rkey=self`. RN's
/// `useNotificationDeclarationQuery` treats a missing record as
/// `allowSubscriptions: 'followers'` — we do the same.
struct ActivityPrivacySettingsScreen: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let initialAccount: Account?

    @State private var model: ActivityPrivacySettingsViewModel

    init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        currentAccount: Account?
    ) {
        self.network = network
        self.accountStore = accountStore
        self.initialAccount = currentAccount
        _model = State(
            initialValue: ActivityPrivacySettingsViewModel(
                network: network,
                accountStore: accountStore,
                account: currentAccount
            )
        )
    }

    var body: some View {
        Form {
            Section {
                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 16)
                        Spacer()
                    }
                } else if model.loadFailed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Failed to load preference.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    optionRow(
                        title: "Anyone who follows me",
                        value: .followers
                    )
                    optionRow(
                        title: "Only followers who I follow",
                        value: .mutuals
                    )
                    optionRow(
                        title: "No one",
                        value: .none
                    )
                }
            } header: {
                Text("Allow others to be notified of your posts")
            } footer: {
                Text("This feature allows users to receive notifications for your new posts and replies. Who do you want to enable this for?")
            }
        }
        .navigationTitle("Activity privacy")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.refresh() }
        .alert("Couldn't update", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            if let msg = model.errorMessage { Text(msg) }
        }
    }

    /// Single radio row. Tapping triggers an optimistic write; the row is
    /// disabled while a write is in flight to avoid double-taps.
    @ViewBuilder
    private func optionRow(title: String, value: AllowSubscriptions) -> some View {
        Button {
            guard model.allowSubscriptions != value else { return }
            Task { await model.setAllowSubscriptions(value) }
        } label: {
            HStack {
                Image(systemName: model.allowSubscriptions == value
                      ? "largecircle.fill.circle"
                      : "circle")
                    .foregroundStyle(model.allowSubscriptions == value
                                     ? Color.accentColor
                                     : Color.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isUpdating)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.allowSubscriptions == value
                                ? [.isButton, .isSelected]
                                : .isButton)
    }
}

// MARK: - View model

@MainActor
@Observable
final class ActivityPrivacySettingsViewModel {

    /// Currently-selected visibility. Defaults to `followers` to match RN's
    /// "no record yet" fallback in `useNotificationDeclarationQuery`.
    var allowSubscriptions: AllowSubscriptions = .followers

    var isLoading = false
    var isUpdating = false
    /// `true` after a load attempt failed (and we have no fallback record to
    /// show). Drives the inline error placeholder. Distinct from
    /// `errorMessage`, which is for write failures.
    var loadFailed = false
    var errorMessage: String?

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private(set) var account: Account?

    init(network: any NetworkClient, accountStore: any AccountStore, account: Account?) {
        self.network = network
        self.accountStore = accountStore
        self.account = account
    }

    // MARK: - Refresh

    /// Loads the current activity-privacy declaration. A "record not found"
    /// error is treated as success with the default `.followers` value
    /// (matches RN's `useNotificationDeclarationQuery` fallback).
    func refresh() async {
        guard let did = await currentDID() else {
            loadFailed = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        loadFailed = false
        do {
            let resp: GetRecordResponse<NotificationDeclarationRecord> = try await network.get(
                lexicon: "com.atproto.repo.getRecord",
                params: [
                    "repo": did.rawValue,
                    "collection": "app.bsky.notification.declaration",
                    "rkey": "self",
                ]
            )
            allowSubscriptions = resp.value.allowSubscriptions
        } catch {
            // No declaration yet → start from RN's default rather than
            // showing an error. We only flip `loadFailed` for non-"missing"
            // errors so users can still pick a value on a brand-new account.
            let message = error.localizedDescription.lowercased()
            if message.contains("could not locate record")
                || message.contains("recordnotfound")
                || message.contains("not found") {
                logger.debug("notification.declaration not found; using default 'followers'")
                allowSubscriptions = .followers
            } else {
                logger.error("getRecord(notification.declaration) failed: \(error.localizedDescription, privacy: .public)")
                loadFailed = true
            }
        }
    }

    // MARK: - Write

    /// Optimistically updates `allowSubscriptions` and writes the new record
    /// back via `com.atproto.repo.putRecord`. Rolls back on failure and
    /// surfaces an alert.
    func setAllowSubscriptions(_ next: AllowSubscriptions) async {
        guard let did = await currentDID() else {
            errorMessage = "Couldn't find your account."
            return
        }
        let previous = allowSubscriptions
        allowSubscriptions = next
        isUpdating = true
        defer { isUpdating = false }

        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.putRecord",
                body: PutRecordRequest(
                    repo: did.rawValue,
                    collection: "app.bsky.notification.declaration",
                    rkey: "self",
                    record: NotificationDeclarationRecord(allowSubscriptions: next)
                )
            )
        } catch {
            logger.error("putRecord(notification.declaration) failed: \(error.localizedDescription, privacy: .public)")
            allowSubscriptions = previous
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func currentDID() async -> DID? {
        if let did = account?.did { return did }
        do {
            return try await accountStore.loadCurrentDID()
        } catch {
            logger.debug("loadCurrentDID failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("ActivityPrivacySettingsScreen — Light") {
    NavigationStack {
        ActivityPrivacySettingsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            currentAccount: Account(
                did: DID(rawValue: "did:plc:preview"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: true,
                status: nil
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ActivityPrivacySettingsScreen — Dark") {
    NavigationStack {
        ActivityPrivacySettingsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            currentAccount: Account(
                did: DID(rawValue: "did:plc:preview"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: true,
                status: nil
            )
        )
    }
    .preferredColorScheme(.dark)
}
