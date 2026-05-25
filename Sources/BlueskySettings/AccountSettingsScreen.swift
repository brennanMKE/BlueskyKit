import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "AccountSettings"
)

// MARK: - AccountSettingsScreen

/// Hub for account-level settings, mirroring `Bluesky-ReactNative/src/screens/Settings/AccountSettings.tsx`.
///
/// Row order matches RN:
/// Email · Verify email (when not confirmed) · Update email · Password ·
/// Handle · Birthday · Export my data · Deactivate · Delete.
///
/// Row functionality vs. defer-to-bsky.app:
/// - **Functional (in-app):** verify email (request confirmation), update
///   email (request token then submit new email), birthday (read + write
///   `personalDetailsPref`), deactivate account.
/// - **Deferred to bsky.app:** change password (handled today by the existing
///   forgot-password flow, so we direct the user there), change handle
///   (placeholder; needs a domain-suffix selector + availability check),
///   export my data (CAR download is a download flow not yet built),
///   delete account (high-stakes; defer).
public struct AccountSettingsScreen: View {

    private let network: any NetworkClient
    private let initialAccount: Account?
    /// Called after a successful `deactivateAccount`. The host is expected to
    /// log out the current session so the user re-authenticates and the
    /// RootView gate routes them to `DeactivatedView`. Mirrors RN's
    /// `logoutCurrentAccount('Deactivated')` follow-up.
    private let onDeactivated: () -> Void
    /// Optional override for the bsky.app deep-link target (used for password,
    /// export, delete rows that punt to the web app).
    private let externalAccountSettingsURL: URL

    @State private var model: AccountSettingsViewModel
    @State private var presentingSheet: SheetKind?

    public init(
        network: any NetworkClient,
        account: Account?,
        onDeactivated: @escaping () -> Void,
        externalAccountSettingsURL: URL = URL(string: "https://bsky.app/settings/account")!
    ) {
        self.network = network
        self.initialAccount = account
        self.onDeactivated = onDeactivated
        self.externalAccountSettingsURL = externalAccountSettingsURL
        _model = State(initialValue: AccountSettingsViewModel(network: network, account: account))
    }

    public var body: some View {
        Form {
            // MARK: Email

            Section {
                emailRow
                if let account = model.account, account.emailConfirmed != true {
                    verifyEmailRow
                }
                Button {
                    presentingSheet = .updateEmail
                } label: {
                    Label("Update email", systemImage: "pencil.line")
                }
            } header: {
                Text("Email")
            }

            // MARK: Password

            Section {
                Button {
                    presentingSheet = .changePassword
                } label: {
                    Label("Password", systemImage: "lock")
                }
            }

            // MARK: Handle

            Section {
                handleRow
                Button {
                    presentingSheet = .changeHandle
                } label: {
                    Label("Change handle", systemImage: "at")
                }
            } header: {
                Text("Handle")
            }

            // MARK: Birthday

            Section {
                birthdayRow
            } header: {
                Text("Birthday")
            }

            // MARK: Export

            Section {
                Button {
                    presentingSheet = .exportData
                } label: {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                }
            }

            // MARK: Deactivate / Delete

            Section {
                Button(role: .destructive) {
                    presentingSheet = .deactivate
                } label: {
                    Label("Deactivate account", systemImage: "snowflake")
                }
                Button(role: .destructive) {
                    presentingSheet = .deleteAccount
                } label: {
                    Label("Delete account", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-settings-screen")
        .navigationTitle("Account")
        .task { await model.refreshFromServer() }
        .sheet(item: $presentingSheet) { kind in
            switch kind {
            case .updateEmail:
                UpdateEmailSheet(model: model, dismiss: { presentingSheet = nil })
            case .changePassword:
                ChangePasswordReferralSheet(
                    bskyAppURL: externalAccountSettingsURL,
                    dismiss: { presentingSheet = nil }
                )
            case .changeHandle:
                ChangeHandleSheet(
                    bskyAppURL: externalAccountSettingsURL,
                    dismiss: { presentingSheet = nil }
                )
            case .deactivate:
                DeactivateAccountSheet(
                    model: model,
                    onDeactivated: {
                        presentingSheet = nil
                        onDeactivated()
                    },
                    dismiss: { presentingSheet = nil }
                )
            case .deleteAccount:
                DeleteAccountSheet(
                    bskyAppURL: externalAccountSettingsURL,
                    dismiss: { presentingSheet = nil }
                )
            case .exportData:
                ExportDataSheet(
                    bskyAppURL: externalAccountSettingsURL,
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
        .alert("Verification email sent", isPresented: $model.showVerificationSentToast) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your inbox to confirm your address.")
        }
    }

    // MARK: - Rows

    private var emailRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Email", systemImage: "envelope")
            Spacer()
            if let email = model.account?.email, !email.isEmpty {
                Text(email)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("(no email)").foregroundStyle(.secondary)
            }
            if model.account?.emailConfirmed == true {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Verified")
            }
        }
    }

    private var verifyEmailRow: some View {
        Button {
            Task { await model.requestEmailConfirmation() }
        } label: {
            HStack {
                Label("Verify your email", systemImage: "checkmark.shield")
                Spacer()
                if model.isVerifyingEmail { ProgressView().controlSize(.small) }
            }
        }
        .disabled(model.isVerifyingEmail)
    }

    private var handleRow: some View {
        HStack {
            Label("Handle", systemImage: "at")
            Spacer()
            if let handle = model.account?.handle.rawValue {
                Text("@\(handle)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var birthdayRow: some View {
        HStack {
            Label("Birthday", systemImage: "birthday.cake")
            Spacer()
            if model.isLoadingBirthday {
                ProgressView().controlSize(.small)
            } else if let bd = model.birthDate {
                Text(bd.formatted(date: .long, time: .omitted))
                    .foregroundStyle(.secondary)
            } else {
                Text("Not set").foregroundStyle(.secondary)
            }
            DatePicker(
                "",
                selection: Binding(
                    get: { model.birthDate ?? Date() },
                    set: { newValue in
                        Task { await model.updateBirthDate(newValue) }
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
        }
    }
}

// MARK: - Sheet kinds

private enum SheetKind: Identifiable, Hashable {
    case updateEmail, changePassword, changeHandle, deactivate, deleteAccount, exportData
    var id: Self { self }
}

// MARK: - View model

@MainActor
@Observable
final class AccountSettingsViewModel {

    /// Current snapshot of the account being edited. `email`,
    /// `emailConfirmed`, and `handle` may drift from `SessionManager` until
    /// the parent re-resolves; the screen treats this as the source of truth
    /// for display.
    var account: Account?

    /// Birth date pulled from `app.bsky.actor.getPreferences`'s
    /// `personalDetailsPref`. `nil` until loaded; remains `nil` if the
    /// account has none stored.
    var birthDate: Date?
    var isLoadingBirthday = false

    var isVerifyingEmail = false
    var showVerificationSentToast = false

    var errorMessage: String?

    private let network: any NetworkClient

    init(network: any NetworkClient, account: Account?) {
        self.network = network
        self.account = account
    }

    // MARK: Refresh

    /// Pulls fresh email + verification status from `getSession` and the
    /// birthday from `getPreferences`. Both calls are best-effort and log on
    /// failure rather than surfacing alerts.
    func refreshFromServer() async {
        await refreshSession()
        await refreshBirthday()
    }

    private func refreshSession() async {
        do {
            let resp: GetSessionResponse = try await network.get(
                lexicon: "com.atproto.server.getSession",
                params: [:]
            )
            if let current = account {
                let merged = Account(
                    did: current.did,
                    handle: Handle(rawValue: resp.handle),
                    displayName: current.displayName,
                    avatarURL: current.avatarURL,
                    serviceEndpoint: current.serviceEndpoint,
                    email: resp.email ?? current.email,
                    emailConfirmed: resp.emailConfirmed ?? current.emailConfirmed,
                    status: current.status
                )
                self.account = merged
            }
        } catch {
            logger.debug("getSession refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshBirthday() async {
        isLoadingBirthday = true
        defer { isLoadingBirthday = false }
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            self.birthDate = resp.birthDate
        } catch {
            logger.debug("getPreferences refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Email confirmation

    /// `com.atproto.server.requestEmailConfirmation` — the PDS sends a code to
    /// the registered email. We surface a one-shot success toast; the user
    /// completes verification by clicking the link in the email (no in-app
    /// confirm step today).
    func requestEmailConfirmation() async {
        isVerifyingEmail = true
        defer { isVerifyingEmail = false }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.server.requestEmailConfirmation",
                body: EmptyBody()
            )
            showVerificationSentToast = true
        } catch {
            logger.error("requestEmailConfirmation failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Email update

    /// Step 1 of update-email: ask the server whether a confirmation token is
    /// required for the change. Returns `tokenRequired`.
    func requestEmailUpdate() async throws -> Bool {
        let resp: RequestEmailUpdateResponse = try await network.post(
            lexicon: "com.atproto.server.requestEmailUpdate",
            body: EmptyBody()
        )
        return resp.tokenRequired
    }

    /// Step 2 of update-email: submit the new address (and the optional
    /// token). Refreshes the session snapshot on success.
    func updateEmail(newEmail: String, token: String?) async throws {
        let _: EmptyResponse = try await network.post(
            lexicon: "com.atproto.server.updateEmail",
            body: UpdateEmailRequest(email: newEmail, token: token)
        )
        await refreshSession()
    }

    // MARK: Birthday

    /// Writes a `personalDetailsPref` carrying the new birth date. RN does
    /// the same via `agent.setPersonalDetails({birthDate})`. The local
    /// `birthDate` flips optimistically and rolls back on failure.
    func updateBirthDate(_ newValue: Date) async {
        let previous = birthDate
        birthDate = newValue
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences",
                body: PutPreferencesRequest(birthDate: newValue)
            )
        } catch {
            logger.error("putPreferences(birthDate) failed: \(error.localizedDescription, privacy: .public)")
            birthDate = previous
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Deactivate

    /// `com.atproto.server.deactivateAccount` with no `deleteAfter` — RN's
    /// dialog also passes an empty body. After a successful response the
    /// caller is expected to log the user out so the gate routes them to
    /// `DeactivatedView` on the next sign-in.
    func deactivateAccount() async throws {
        let _: EmptyResponse = try await network.post(
            lexicon: "com.atproto.server.deactivateAccount",
            body: DeactivateAccountRequest()
        )
    }
}

// MARK: - Update email sheet

private struct UpdateEmailSheet: View {
    @Bindable var model: AccountSettingsViewModel
    let dismiss: () -> Void

    @State private var stage: Stage = .enterEmail
    @State private var newEmail: String = ""
    @State private var token: String = ""
    @State private var requiresToken = false
    @State private var isSubmitting = false
    @State private var localError: String?

    private enum Stage { case enterEmail, enterToken, done }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch stage {
                    case .enterEmail:
                        TextField("New email", text: $newEmail)
                            #if !os(macOS)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    case .enterToken:
                        Text("We sent a confirmation code to your current email. Paste it below to finish updating your address.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("Confirmation code", text: $token)
                            #if !os(macOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .autocorrectionDisabled()
                        TextField("New email", text: $newEmail)
                            .disabled(true)
                            .foregroundStyle(.secondary)
                    case .done:
                        Label("Email updated", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Your address is now \(newEmail).")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if let localError {
                        Text(localError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Update email")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if stage == .done {
                        Button("Done", action: dismiss)
                    } else {
                        Button(stage == .enterEmail ? "Next" : "Submit") {
                            Task { await primaryAction() }
                        }
                        .disabled(isSubmitting || !canSubmitCurrentStage)
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 260)
    }

    private var canSubmitCurrentStage: Bool {
        switch stage {
        case .enterEmail:
            return SignupValidation.isLikelyEmail(newEmail)
        case .enterToken:
            return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .done:
            return true
        }
    }

    private func primaryAction() async {
        localError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        switch stage {
        case .enterEmail:
            do {
                requiresToken = try await model.requestEmailUpdate()
                if requiresToken {
                    stage = .enterToken
                } else {
                    // PDS doesn't require a token — submit immediately.
                    try await model.updateEmail(newEmail: newEmail, token: nil)
                    stage = .done
                }
            } catch {
                localError = error.localizedDescription
            }
        case .enterToken:
            do {
                try await model.updateEmail(newEmail: newEmail, token: token)
                stage = .done
            } catch {
                localError = error.localizedDescription
            }
        case .done:
            break
        }
    }
}

// MARK: - Deactivate sheet

private struct DeactivateAccountSheet: View {
    let model: AccountSettingsViewModel
    let onDeactivated: () -> Void
    let dismiss: () -> Void

    @State private var isSubmitting = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your profile, posts, feeds, and lists will no longer be visible to other Bluesky users. You can reactivate your account at any time by signing in.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("There is no time limit for account deactivation, come back any time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("If you're trying to change your handle or email, do so before you deactivate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let localError {
                    Section {
                        Text(localError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Deactivate account")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        Task { await deactivate() }
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Deactivate")
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 280)
    }

    private func deactivate() async {
        localError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.deactivateAccount()
            onDeactivated()
        } catch {
            localError = error.localizedDescription
        }
    }
}

// MARK: - Referral sheets (deferred to bsky.app)

/// Shared "manage on bsky.app" sheet. Each deferred row reuses this scaffold
/// with its own copy + open-in-browser CTA.
private struct ReferralSheet: View {
    let title: String
    let message: String
    let bskyAppURL: URL
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        openURL(bskyAppURL)
                    } label: {
                        Label("Open bsky.app", systemImage: "safari")
                    }
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
        .frame(minWidth: 380, minHeight: 240)
    }
}

private struct ChangePasswordReferralSheet: View {
    let bskyAppURL: URL
    let dismiss: () -> Void

    var body: some View {
        ReferralSheet(
            title: "Change password",
            message: "Use the Forgot Password flow on the sign-in screen to change your password — it sends a reset code to your registered email. You can also manage your password on bsky.app.",
            bskyAppURL: bskyAppURL,
            dismiss: dismiss
        )
    }
}

private struct ChangeHandleSheet: View {
    let bskyAppURL: URL
    let dismiss: () -> Void

    var body: some View {
        ReferralSheet(
            title: "Change handle",
            message: "Changing your handle (or pointing at a domain you own) is currently managed on bsky.app. The full in-app flow with availability checks and custom-domain verification is coming in a later release.",
            bskyAppURL: bskyAppURL,
            dismiss: dismiss
        )
    }
}

private struct DeleteAccountSheet: View {
    let bskyAppURL: URL
    let dismiss: () -> Void

    var body: some View {
        ReferralSheet(
            title: "Delete account",
            message: "Permanent account deletion is a high-stakes operation handled on bsky.app for now. If you only want to take a break, use Deactivate account instead — it's reversible.",
            bskyAppURL: bskyAppURL,
            dismiss: dismiss
        )
    }
}

private struct ExportDataSheet: View {
    let bskyAppURL: URL
    let dismiss: () -> Void

    var body: some View {
        ReferralSheet(
            title: "Export my data",
            message: "Your Bluesky repo can be downloaded as a CAR file from bsky.app. The in-app download flow is coming in a later release.",
            bskyAppURL: bskyAppURL,
            dismiss: dismiss
        )
    }
}

// MARK: - Previews

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("AccountSettingsScreen — Light") {
    NavigationStack {
        AccountSettingsScreen(
            network: PreviewNoOpNetwork(),
            account: Account(
                did: DID(rawValue: "did:plc:preview"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: false,
                status: nil
            ),
            onDeactivated: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("AccountSettingsScreen — Dark") {
    NavigationStack {
        AccountSettingsScreen(
            network: PreviewNoOpNetwork(),
            account: Account(
                did: DID(rawValue: "did:plc:preview"),
                handle: Handle(rawValue: "alice.bsky.social"),
                displayName: "Alice",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "alice@example.com",
                emailConfirmed: true,
                status: nil
            ),
            onDeactivated: {}
        )
    }
    .preferredColorScheme(.dark)
}
