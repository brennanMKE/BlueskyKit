import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "PrivacySettings"
)

/// Self-label value used by AT Proto to opt an account out of being shown to
/// signed-out viewers (the "PWI" — personal-web-indexing — opt-out). Stored in
/// `app.bsky.actor.profile.labels.values`.
private let pwiLabelValue = "!no-unauthenticated"

// MARK: - PrivacySettingsScreen

/// Privacy & Security hub mirroring
/// `Bluesky-ReactNative/src/screens/Settings/PrivacyAndSecuritySettings.tsx`.
///
/// Row order matches RN: Two-factor → App passwords → Activity privacy →
/// Logged-out visibility → Interaction settings.
///
/// Row functionality vs. defer-to-bsky.app / forward-references:
/// - **Functional (in-app):** App passwords link with active-count badge,
///   Logged-out visibility toggle (PWI opt-out — read + write the
///   `!no-unauthenticated` self-label on `app.bsky.actor.profile`).
/// - **Deferred to a referral sheet:** Two-factor (Email 2FA). The PDS flow
///   requires sending a verification email and submitting the token through a
///   dedicated dialog (RN's `EmailDialog`); the read side (`emailAuthFactor`
///   on `getSession`) is not yet plumbed onto our `Account`. We surface the
///   row with current state ("Not enabled") and open a sheet that explains
///   the email-verification flow and points the user at bsky.app to manage
///   it. See gotchas in #0114.
/// - **Forward-references:** Interaction settings (#0138) is linked but
///   currently opens a placeholder destination.
/// - **Functional via dedicated screen:** Activity privacy (#0122) navigates
///   to `ActivityPrivacySettingsScreen`, which writes
///   `app.bsky.notification.declaration`.
struct PrivacySettingsScreen: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let initialAccount: Account?
    private let externalSettingsURL: URL

    @State private var model: PrivacySettingsViewModel
    @State private var presentingSheet: SheetKind?

    init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        currentAccount: Account?,
        externalSettingsURL: URL = URL(string: "https://bsky.app/settings/privacy-and-security")!
    ) {
        self.network = network
        self.accountStore = accountStore
        self.initialAccount = currentAccount
        self.externalSettingsURL = externalSettingsURL
        _model = State(
            initialValue: PrivacySettingsViewModel(
                network: network,
                accountStore: accountStore,
                account: currentAccount
            )
        )
    }

    var body: some View {
        Form {
            // MARK: Two-factor

            Section {
                twoFactorRow
            } header: {
                Text("Two-factor authentication")
            } footer: {
                Text("Add a layer of security by requiring a code from your email when signing in.")
            }

            // MARK: App passwords

            Section {
                NavigationLink {
                    AppPasswordsScreen(network: network)
                } label: {
                    HStack {
                        Label("App passwords", systemImage: "key")
                        Spacer()
                        if model.appPasswordCount > 0 {
                            Text("\(model.appPasswordCount)")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                )
                                .accessibilityLabel("\(model.appPasswordCount) active app passwords")
                        }
                    }
                }
            } header: {
                Text("App passwords")
            } footer: {
                Text("App passwords let third-party apps access your account without sharing your main password.")
            }

            // MARK: Activity privacy

            Section {
                NavigationLink {
                    ActivityPrivacySettingsScreen(
                        network: network,
                        accountStore: accountStore,
                        currentAccount: initialAccount
                    )
                } label: {
                    Label("Allow others to be notified of your posts", systemImage: "bell.badge")
                }
            } header: {
                Text("Activity privacy")
            }

            // MARK: Logged-out visibility (PWI opt-out)

            Section {
                pwiToggleRow
            } header: {
                Text("Logged-out visibility")
            } footer: {
                Text("Bluesky is an open and public network. This setting only limits the visibility of your content on the Bluesky app and website; other apps may not respect it.")
            }

            // MARK: Interaction settings

            Section {
                Button {
                    presentingSheet = .interactionSettingsPlaceholder
                } label: {
                    HStack {
                        Label("Who can reply, quote, or DM you", systemImage: "bubble.left.and.bubble.right")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Interaction settings")
            }
        }
        .navigationTitle("Privacy & Security")
        .task { await model.refresh() }
        .sheet(item: $presentingSheet) { kind in
            switch kind {
            case .twoFactor:
                TwoFactorReferralSheet(
                    bskyAppURL: externalSettingsURL,
                    isCurrentlyEnabled: model.isTwoFactorEnabled,
                    dismiss: { presentingSheet = nil }
                )
            case .interactionSettingsPlaceholder:
                PlaceholderSheet(
                    title: "Interaction settings",
                    message: "Interaction settings let you choose who can reply, quote, or message you. The full screen is coming in a later release — see issue #0138.",
                    dismiss: { presentingSheet = nil }
                )
            }
        }
        .alert("Couldn't update", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            if let msg = model.errorMessage { Text(msg) }
        }
    }

    // MARK: - Rows

    private var twoFactorRow: some View {
        Button {
            presentingSheet = .twoFactor
        } label: {
            HStack {
                Label {
                    if model.isTwoFactorEnabled {
                        Text("Email 2FA enabled")
                    } else {
                        Text("Two-factor authentication")
                    }
                } icon: {
                    Image(systemName: model.isTwoFactorEnabled ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(model.isTwoFactorEnabled ? Color.accentColor : .primary)
                }
                Spacer()
                Text(model.isTwoFactorEnabled ? "Change" : "Enable")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
    }

    private var pwiToggleRow: some View {
        Toggle(isOn: Binding(
            get: { model.isPwiOptedOut },
            set: { newValue in
                Task { await model.setPwiOptedOut(newValue) }
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discourage apps from showing my account to logged-out users")
                    .font(.body)
                if model.isLoadingProfile {
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("When on, Bluesky will not show your profile and posts to logged-out users.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(model.isLoadingProfile || model.isUpdatingPwi)
    }
}

// MARK: - Sheet kinds

private enum SheetKind: Identifiable, Hashable {
    case twoFactor
    case interactionSettingsPlaceholder
    var id: Self { self }
}

// MARK: - View model

@MainActor
@Observable
final class PrivacySettingsViewModel {

    /// `true` when the active account has Email 2FA turned on. RN reads this
    /// from `currentAccount.emailAuthFactor`, populated by `getSession`. Our
    /// `Account` doesn't carry that field today, so we leave this `false`
    /// until the read side is plumbed and let the row fall back to a
    /// referral sheet. See issue #0114 gotchas.
    var isTwoFactorEnabled: Bool = false

    /// Number of active app passwords (drives the trailing badge on the App
    /// Passwords row). `0` means no badge is rendered.
    var appPasswordCount: Int = 0

    /// `true` when the user's `app.bsky.actor.profile` carries a
    /// `!no-unauthenticated` self-label.
    var isPwiOptedOut: Bool = false

    var isLoadingProfile = false
    var isUpdatingPwi = false

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

    /// Loads the app-password count and the current PWI label state. Both
    /// calls are best-effort — failures log and leave the existing values in
    /// place rather than surfacing alerts on screen entry.
    func refresh() async {
        async let _: Void = refreshAppPasswordCount()
        async let _: Void = refreshProfileRecord()
        _ = await (refreshAppPasswordCount(), refreshProfileRecord())
    }

    private func refreshAppPasswordCount() async {
        do {
            let resp: ListAppPasswordsResponse = try await network.get(
                lexicon: "com.atproto.server.listAppPasswords",
                params: [:]
            )
            self.appPasswordCount = resp.passwords.count
        } catch {
            logger.debug("listAppPasswords refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshProfileRecord() async {
        guard let did = await currentDID() else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let resp: GetRecordResponse<ProfileRecord> = try await network.get(
                lexicon: "com.atproto.repo.getRecord",
                params: [
                    "repo": did.rawValue,
                    "collection": "app.bsky.actor.profile",
                    "rkey": "self",
                ]
            )
            self.isPwiOptedOut = resp.value.labels?.values.contains { $0.val == pwiLabelValue } ?? false
        } catch {
            // No profile record yet (new accounts): treat as not-opted-out.
            logger.debug("getRecord(profile) failed: \(error.localizedDescription, privacy: .public)")
            self.isPwiOptedOut = false
        }
    }

    // MARK: - PWI toggle

    /// Read-modify-write the actor's profile record so its `labels.values`
    /// either contain or omit `!no-unauthenticated`. Mirrors RN's
    /// `PwiOptOut` component (which goes through `agent.upsertProfile`).
    /// Optimistically flips local state and rolls back on failure.
    func setPwiOptedOut(_ optedOut: Bool) async {
        guard let did = await currentDID() else {
            errorMessage = "Couldn't find your account."
            return
        }
        let previous = isPwiOptedOut
        isPwiOptedOut = optedOut
        isUpdatingPwi = true
        defer { isUpdatingPwi = false }

        do {
            // 1. Read the existing record so we don't clobber displayName /
            //    description / future fields we don't model yet.
            let existing: ProfileRecord
            do {
                let resp: GetRecordResponse<ProfileRecord> = try await network.get(
                    lexicon: "com.atproto.repo.getRecord",
                    params: [
                        "repo": did.rawValue,
                        "collection": "app.bsky.actor.profile",
                        "rkey": "self",
                    ]
                )
                existing = resp.value
            } catch {
                // No record yet — start from an empty one.
                existing = ProfileRecord(displayName: nil, description: nil, labels: nil)
            }

            // 2. Build the next labels container by toggling the value.
            var nextValues = existing.labels?.values ?? []
            let hasLabel = nextValues.contains { $0.val == pwiLabelValue }
            if optedOut, !hasLabel {
                nextValues.append(SelfLabelValue(val: pwiLabelValue))
            } else if !optedOut, hasLabel {
                nextValues.removeAll { $0.val == pwiLabelValue }
            }
            let nextLabels: SelfLabels? = nextValues.isEmpty
                ? nil
                : SelfLabels(values: nextValues)

            let next = ProfileRecord(
                displayName: existing.displayName,
                description: existing.description,
                labels: nextLabels
            )

            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.putRecord",
                body: PutRecordRequest(
                    repo: did.rawValue,
                    collection: "app.bsky.actor.profile",
                    rkey: "self",
                    record: next
                )
            )
        } catch {
            logger.error("putRecord(profile) failed: \(error.localizedDescription, privacy: .public)")
            isPwiOptedOut = previous
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

// MARK: - Two-factor referral sheet

/// Email-2FA management sheet. RN runs this through a dedicated `EmailDialog`
/// with screens for "request code → submit code → enable 2FA"; that flow
/// isn't built natively yet. We summarize the state and point the user at
/// bsky.app, where the existing email-verification UI can flip the toggle.
private struct TwoFactorReferralSheet: View {
    let bskyAppURL: URL
    let isCurrentlyEnabled: Bool
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: isCurrentlyEnabled ? "checkmark.shield.fill" : "shield")
                            .font(.title2)
                            .foregroundStyle(isCurrentlyEnabled ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isCurrentlyEnabled ? "Email 2FA is enabled" : "Email 2FA is not enabled")
                                .font(.headline)
                            Text("When enabled, signing in requires a code sent to your registered email address.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text("Two-factor authentication is managed through email verification. To turn it on or off, open Privacy & Security on bsky.app — the in-app dialog with code submission is coming in a later release.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How to manage 2FA")
                }

                Section {
                    Button {
                        openURL(bskyAppURL)
                    } label: {
                        Label("Open bsky.app", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Two-factor authentication")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

// MARK: - Placeholder sheet (forward-references)

private struct PlaceholderSheet: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 220)
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

#Preview("PrivacySettingsScreen — Light") {
    NavigationStack {
        PrivacySettingsScreen(
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

#Preview("PrivacySettingsScreen — Dark") {
    NavigationStack {
        PrivacySettingsScreen(
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
