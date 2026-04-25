import SwiftUI
import BlueskyCore
import BlueskyKit

/// Login form for an AT Protocol account.
///
/// Handles the full sign-in flow: handle/password entry, optional custom PDS URL,
/// and TOTP 2FA when the server returns `AuthFactorTokenRequired`.
public struct LoginView: View {

    private let session: SessionManager
    private let onSuccess: () -> Void

    @State private var handle = ""
    @State private var password = ""
    @State private var serviceURLText = "https://bsky.social"
    @State private var showServiceURL = false
    @State private var authFactorToken = ""
    @State private var needsAuthFactor = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable { case handle, password, authFactor, serviceURL }

    public init(session: SessionManager, onSuccess: @escaping () -> Void) {
        self.session = session
        self.onSuccess = onSuccess
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                form
                if let error = errorMessage {
                    errorBanner(error)
                }
                signInButton
                customServerToggle
            }
            .padding(24)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Sign in to Bluesky")
                .font(.title2.bold())
            Text("Enter your username and password")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private var form: some View {
        VStack(spacing: 12) {
            fieldRow(label: "Username or email") {
                TextField("user.bsky.social", text: $handle)
                    .focused($focus, equals: .handle)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
#if os(iOS)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
#endif
            }

            fieldRow(label: "Password") {
                SecureField("Password", text: $password)
                    .focused($focus, equals: .password)
                    .submitLabel(needsAuthFactor ? .next : .go)
                    .onSubmit { needsAuthFactor ? (focus = .authFactor) : handleSubmit() }
#if os(iOS)
                    .textContentType(.password)
#endif
            }

            if needsAuthFactor {
                fieldRow(label: "Two-factor code") {
                    TextField("XXXXXX", text: $authFactorToken)
                        .focused($focus, equals: .authFactor)
                        .submitLabel(.go)
                        .onSubmit { handleSubmit() }
#if os(iOS)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
#endif
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showServiceURL {
                fieldRow(label: "Hosting provider") {
                    TextField("https://bsky.social", text: $serviceURLText)
                        .focused($focus, equals: .serviceURL)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
#if os(iOS)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: needsAuthFactor)
        .animation(.easeInOut(duration: 0.2), value: showServiceURL)
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var signInButton: some View {
        Button(action: handleSubmit) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(needsAuthFactor ? "Verify" : "Sign in")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading || handle.isEmpty || password.isEmpty)
    }

    private var customServerToggle: some View {
        Button {
            withAnimation { showServiceURL.toggle() }
        } label: {
            Text(showServiceURL ? "Use default server" : "Use a custom server")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func handleSubmit() {
        guard !isLoading, !handle.isEmpty, !password.isEmpty else { return }
        Task { await signIn() }
    }

    @MainActor
    private func signIn() async {
        isLoading = true
        errorMessage = nil
        focus = nil
        defer { isLoading = false }

        if let url = URL(string: serviceURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme?.hasPrefix("http") == true {
            session.serviceURL = url
        }

        do {
            try await session.login(
                identifier: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                authFactorToken: needsAuthFactor ? authFactorToken.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            )
            onSuccess()
        } catch ATError.authFactorTokenRequired {
            withAnimation {
                needsAuthFactor = true
                errorMessage = nil
            }
            focus = .authFactor
        } catch ATError.xrpc(let code, let message) {
            errorMessage = message.isEmpty ? code : message
        } catch ATError.network(let urlError) {
            errorMessage = urlError.localizedDescription
        } catch ATError.httpStatus(let code) {
            errorMessage = "Server error (\(code)). Check your hosting provider."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

private final class PreviewAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

private final class PreviewNetworkClient: NetworkClient, @unchecked Sendable {
    nonisolated func get<Response: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> Response {
        throw ATError.unknown("preview")
    }
    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(lexicon: String, body: Body) async throws -> Response {
        throw ATError.unknown("preview")
    }
    nonisolated func upload<Response: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> Response {
        throw ATError.unknown("preview")
    }
}

#Preview("Login") {
    LoginView(
        session: SessionManager(accountStore: PreviewAccountStore(), network: PreviewNetworkClient()),
        onSuccess: {}
    )
}
