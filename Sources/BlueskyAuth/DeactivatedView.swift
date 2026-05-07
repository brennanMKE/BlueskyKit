import SwiftUI
import BlueskyCore
import BlueskyKit

/// Holding screen shown above `MainTabView` when the active session belongs to
/// an account whose `status` is `.deactivated`.
///
/// Mirrors RN `screens/Deactivated.tsx`:
///   * Welcome banner explaining the deactivated state for `@<handle>`.
///   * Primary "Yes, reactivate my account" button → calls
///     `SessionManager.activateAccount()`, then refreshes the session so the
///     parent gate can route back to `MainTabView`.
///   * Secondary "Cancel" button → signs the current account out.
///   * Inline error banner for the App-Password edge case ("Bad token scope")
///     and generic failures.
///   * Optional `AccountPickerView` when there are other stored accounts so
///     the user can switch to a non-deactivated one.
///
/// `BlueskyAuth` is Layer 2 and intentionally does not depend on `BlueskyUI`,
/// so styling stays within standard SwiftUI material/colors. The same look
/// will be reused for the takendown / suspended gates (issue #0095) — the
/// status enum and gate plumbing live in the parent `RootView`.
public struct DeactivatedView: View {

    private let session: SessionManager
    private let onReactivated: () -> Void
    private let onSignedOut: () -> Void
    private let onAddAccount: () -> Void

    @State private var isReactivating = false
    @State private var errorMessage: String?

    /// - Parameters:
    ///   - session: the live `SessionManager`. Drives `currentAccount` /
    ///     `accounts` and is used for `activateAccount` / `logout`.
    ///   - onReactivated: invoked after a successful reactivate +
    ///     `refreshCurrentSession`. The host should re-evaluate the gate so
    ///     `MainTabView` can take over.
    ///   - onSignedOut: invoked after the user taps "Cancel" and the current
    ///     account has been signed out. The host should re-evaluate the gate
    ///     and present login.
    ///   - onAddAccount: invoked when the user taps "Sign in or create an
    ///     account" (no other stored accounts case). The host should present
    ///     the login flow without removing the deactivated account from
    ///     storage.
    public init(
        session: SessionManager,
        onReactivated: @escaping () -> Void,
        onSignedOut: @escaping () -> Void,
        onAddAccount: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onReactivated = onReactivated
        self.onSignedOut = onSignedOut
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                logo
                explanationCopy
                actionButtons
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                Divider()
                    .padding(.vertical, 8)
                otherAccountsSection
            }
            .padding(24)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    private var logo: some View {
        Image(systemName: "cloud.fill")
            .font(.system(size: 40))
            .foregroundStyle(.tint)
            .padding(.top, 32)
            .padding(.bottom, 24)
    }

    private var explanationCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back!")
                .font(.title3.weight(.semibold))
            if let handle = session.currentAccount?.handle.rawValue {
                Text("You previously deactivated @\(handle).")
                    .font(.subheadline)
            }
            Text("You can reactivate your account to continue logging in. Your profile and posts will be visible to other users.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: handleReactivate) {
                HStack {
                    if isReactivating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Yes, reactivate my account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReactivating)

            Button(action: handleCancel) {
                Text("Cancel")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isReactivating)
            .accessibilityLabel("Cancel reactivation and sign out")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var otherAccountsSection: some View {
        let hasOtherAccounts = session.accounts.contains { $0.did != session.currentAccount?.did }

        if hasOtherAccounts {
            VStack(alignment: .leading, spacing: 12) {
                Text("Or, sign in to one of your other accounts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AccountPickerView(
                    session: session,
                    onAccountSelected: onReactivated, // re-evaluate gate
                    onAddAccount: onAddAccount
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Or, continue with another account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onAddAccount) {
                    Text("Sign in or create an account")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isReactivating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func handleReactivate() {
        guard !isReactivating else { return }
        Task { await reactivate() }
    }

    @MainActor
    private func reactivate() async {
        isReactivating = true
        errorMessage = nil
        defer { isReactivating = false }

        do {
            try await session.activateAccount()
            // Pull the new status from `getSession` so the gate sees `.active`
            // on the next render.
            _ = try await session.refreshCurrentSession()
            onReactivated()
        } catch ATError.xrpc(let code, let message) {
            // RN special-cases the "Bad token scope" error to nudge App Password
            // users back to a real password (Deactivated.tsx switch on
            // e.message). Fall back to the server message otherwise.
            if code == "InvalidToken" || message.localizedCaseInsensitiveContains("bad token scope") {
                errorMessage = "You're signed in with an App Password. Please sign in with your main password to continue reactivating your account."
            } else if !message.isEmpty {
                errorMessage = message
            } else {
                errorMessage = "Something went wrong, please try again"
            }
        } catch {
            errorMessage = "Something went wrong, please try again"
        }
    }

    private func handleCancel() {
        guard !isReactivating else { return }
        Task { await signOut() }
    }

    @MainActor
    private func signOut() async {
        guard let did = session.currentAccount?.did else {
            onSignedOut()
            return
        }
        do {
            try await session.logout(did: did)
        } catch {
            // Logout failures still flush local state on success paths; swallow
            // and re-route either way so the user is never stuck on this screen.
            errorMessage = error.localizedDescription
        }
        onSignedOut()
    }
}

// MARK: - Preview

private final class PreviewDeactivatedAccountStore: AccountStore, @unchecked Sendable {
    private let stub: [StoredAccount] = [
        StoredAccount(
            account: Account(
                did: DID(rawValue: "did:plc:alice"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: true,
                status: .deactivated
            ),
            accessJwt: "", refreshJwt: ""
        )
    ]
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { stub }
    nonisolated func load(did: DID) async throws -> StoredAccount? { stub.first { $0.account.did == did } }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { DID(rawValue: "did:plc:alice") }
}

private final class PreviewDeactivatedNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("Deactivated — Light") {
    let session = SessionManager(accountStore: PreviewDeactivatedAccountStore(), network: PreviewDeactivatedNetwork())
    DeactivatedView(
        session: session,
        onReactivated: {},
        onSignedOut: {},
        onAddAccount: {}
    )
    .task { await session.restoreLastSession() }
    .preferredColorScheme(.light)
}

#Preview("Deactivated — Dark") {
    let session = SessionManager(accountStore: PreviewDeactivatedAccountStore(), network: PreviewDeactivatedNetwork())
    DeactivatedView(
        session: session,
        onReactivated: {},
        onSignedOut: {},
        onAddAccount: {}
    )
    .task { await session.restoreLastSession() }
    .preferredColorScheme(.dark)
}
