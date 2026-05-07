import SwiftUI
import Foundation
import BlueskyCore
import BlueskyKit

/// Holding screen shown above `MainTabView` when the active session belongs to
/// an account whose `status` is `.takendown` or `.suspended`.
///
/// Mirrors RN `screens/Takendown.tsx`:
///   * Default state: explanatory copy ("Your account has been suspended"),
///     a Terms-of-Service inline link, an "Appeal Suspension" ghost button,
///     and a primary "Sign Out" button.
///   * Appeal state: title flips to "Appeal suspension", a multiline reason
///     `TextField` with a character counter, a "Submit Appeal" primary button,
///     a "Cancel" ghost button.
///   * Success state: replaces the form with "Your appeal has been submitted.
///     If your appeal succeeds, you will receive an email."
///   * Errors render inline in red beneath the form.
///
/// The appeal call is `com.atproto.moderation.createReport` with
/// `reasonType = tools.ozone.report.defs#reasonAppeal`, subject =
/// `com.atproto.admin.defs#repoRef` for the user's own DID, and the
/// `atproto-proxy` header pointing at the Bluesky moderation labeler — i.e.
/// `did:plc:ar7c4by46qjdydhdevvrndac#atproto_labeler`. RN ships
/// `BLUESKY_MOD_SERVICE_HEADERS` for the same purpose.
///
/// `BlueskyAuth` is Layer 2 and intentionally does not depend on `BlueskyUI`,
/// so styling stays within standard SwiftUI material/colors. Pairs with
/// `DeactivatedView` from issue #0094; `RootView` gates both.
public struct TakendownView: View {

    private let session: SessionManager
    private let onSignedOut: () -> Void

    @State private var isAppealing: Bool = false
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var didSubmitSuccessfully: Bool = false
    @State private var errorMessage: String?

    /// Mirrors RN `MAX_REPORT_REASON_GRAPHEME_LENGTH` from
    /// `lib/constants.ts`. Swift's `String.count` returns grapheme cluster
    /// count, so we can compare it directly.
    private static let maxReasonGraphemeLength: Int = 2000

    /// - Parameters:
    ///   - session: live `SessionManager`. Drives `currentAccount` and is
    ///     used for the appeal request and `logout`.
    ///   - onSignedOut: invoked after the user taps "Sign Out" and the
    ///     current account has been signed out. The host should re-evaluate
    ///     the gate and present login.
    public init(
        session: SessionManager,
        onSignedOut: @escaping () -> Void
    ) {
        self.session = session
        self.onSignedOut = onSignedOut
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                logo
                title
                bodyContent
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                Divider()
                    .padding(.vertical, 8)
                actionButtons
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
            .padding(.bottom, 8)
    }

    private var title: some View {
        Text(isAppealing ? "Appeal suspension" : titleForStatus)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// RN uses a single "Your account has been suspended" string for both
    /// `.suspended` and `.takendown`. We mirror that here so the copy stays
    /// in sync with the RN client. (`Takendown.tsx` renders for both.)
    private var titleForStatus: String {
        "Your account has been suspended"
    }

    @ViewBuilder
    private var bodyContent: some View {
        if isAppealing {
            appealForm
        } else {
            explanationCopy
        }
    }

    private var explanationCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            // RN renders the ToS as an inline link inside a single Trans
            // string. SwiftUI's Markdown-style `Text` interpolation gives us
            // the same visual result with a tappable link.
            Text(try! AttributedString(markdown:
                "Your account was found to be in violation of the [Bluesky Social Terms of Service](https://bsky.social/about/support/tos). You have been sent an email outlining the specific violation and suspension period, if applicable. You can appeal this decision if you believe it was made in error."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var appealForm: some View {
        if didSubmitSuccessfully {
            Text("Your appeal has been submitted. If your appeal succeeds, you will receive an email.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reason for appeal")
                    .font(.subheadline.weight(.semibold))

                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $reason)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 150)
                        .background(.quaternary.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isOverMaxLength || errorMessage != nil
                                        ? Color.red.opacity(0.6)
                                        : Color.clear,
                                        lineWidth: 1)
                        )
                        .accessibilityLabel("Reason for appeal")

                    Text("\(reason.count) / \(Self.maxReasonGraphemeLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isOverMaxLength ? .red : .secondary)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private var actionButtons: some View {
        // RN flips primary/secondary based on whether the user is currently
        // composing an appeal:
        //   * appealing + !success → primary "Submit Appeal", ghost "Cancel"
        //   * appealing + success  → primary "Sign Out" (no secondary)
        //   * default              → primary "Sign Out", ghost "Appeal Suspension"
        VStack(spacing: 12) {
            primaryButton
            secondaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isAppealing && !didSubmitSuccessfully {
            Button(action: handleSubmitAppeal) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Submit Appeal")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || isOverMaxLength || reason.isEmpty)
        } else {
            Button(action: handleSignOut) {
                Text("Sign Out")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if isAppealing {
            if !didSubmitSuccessfully {
                Button(action: handleCancelAppeal) {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.quaternary.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        } else {
            Button(action: { isAppealing = true }) {
                Text("Appeal Suspension")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.quaternary.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private var isOverMaxLength: Bool {
        reason.count > Self.maxReasonGraphemeLength
    }

    private func handleSubmitAppeal() {
        guard !isSubmitting, !isOverMaxLength, !reason.isEmpty else { return }
        Task { await submitAppeal() }
    }

    @MainActor
    private func submitAppeal() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await session.submitTakendownAppeal(reason: reason)
            didSubmitSuccessfully = true
            reason = ""
        } catch ATError.xrpc(_, let message) where !message.isEmpty {
            errorMessage = message
        } catch {
            errorMessage = "Something went wrong, please try again"
        }
    }

    private func handleCancelAppeal() {
        guard !isSubmitting else { return }
        isAppealing = false
        errorMessage = nil
    }

    private func handleSignOut() {
        guard !isSubmitting else { return }
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
            // Logout failures still flush local state on success paths;
            // re-route either way so the user is never stuck on this screen.
            errorMessage = error.localizedDescription
        }
        onSignedOut()
    }
}

// MARK: - Preview

private final class PreviewTakendownAccountStore: AccountStore, @unchecked Sendable {
    private let stub: [StoredAccount] = [
        StoredAccount(
            account: Account(
                did: DID(rawValue: "did:plc:bob"),
                handle: Handle(rawValue: "bob.bsky.social"),
                displayName: "Bob",
                avatarURL: nil,
                serviceEndpoint: URL(string: "https://bsky.social")!,
                email: "bob@example.com",
                emailConfirmed: true,
                status: .takendown
            ),
            accessJwt: "", refreshJwt: ""
        )
    ]
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { stub }
    nonisolated func load(did: DID) async throws -> StoredAccount? { stub.first { $0.account.did == did } }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { DID(rawValue: "did:plc:bob") }
}

private final class PreviewTakendownNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("Takendown — Light") {
    let session = SessionManager(accountStore: PreviewTakendownAccountStore(), network: PreviewTakendownNetwork())
    TakendownView(session: session, onSignedOut: {})
        .task { await session.restoreLastSession() }
        .preferredColorScheme(.light)
}

#Preview("Takendown — Dark") {
    let session = SessionManager(accountStore: PreviewTakendownAccountStore(), network: PreviewTakendownNetwork())
    TakendownView(session: session, onSignedOut: {})
        .task { await session.restoreLastSession() }
        .preferredColorScheme(.dark)
}
