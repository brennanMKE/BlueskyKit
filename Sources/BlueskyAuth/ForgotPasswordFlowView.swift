import SwiftUI
import BlueskyCore
import BlueskyKit

/// Three-step password recovery flow that mirrors the React Native client
/// (`screens/Login/ForgotPasswordForm`, `SetNewPasswordForm`,
/// `PasswordUpdatedForm`):
///
/// 1. **Request**     hosting provider + email field; calls
///                    `com.atproto.server.requestPasswordReset`.
/// 2. **SetPassword** reset-code field + new-password field; calls
///                    `com.atproto.server.resetPassword`.
/// 3. **Updated**     confirmation screen with a "Sign in now" CTA that
///                    returns the email to `LoginView`.
///
/// Presented as a sheet from `LoginView`. On completion, the sheet is
/// dismissed and the email used to start the flow is handed back to the
/// caller so it can be pre-filled into the sign-in form.
public struct ForgotPasswordFlowView: View {

    private let session: SessionManager
    /// Invoked when the user finishes the flow. The argument is the email
    /// address used to request the reset, so the host can pre-fill the
    /// sign-in form.
    private let onCompleted: (String) -> Void
    private let onCancel: () -> Void

    @State private var model: ForgotPasswordModel

    public init(
        session: SessionManager,
        initialEmail: String = "",
        onCompleted: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.onCompleted = onCompleted
        self.onCancel = onCancel
        _model = State(initialValue: ForgotPasswordModel(session: session, initialEmail: initialEmail))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader

                Group {
                    switch model.activeStep {
                    case .request:
                        ForgotPasswordRequestView(model: model, onCancel: onCancel)
                    case .setPassword:
                        ForgotPasswordSetView(model: model)
                    case .updated:
                        ForgotPasswordUpdatedView(
                            onSignIn: { onCompleted(model.email) }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(.easeInOut(duration: 0.18), value: model.activeStep)
        .navigationTitle("Reset password")
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(model.activeStep.rawValue + 1) of 3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(model.activeStep.title)
                .font(.title.bold())
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Model

@MainActor
@Observable
final class ForgotPasswordModel {
    enum Step: Int, CaseIterable {
        case request, setPassword, updated
        var title: String {
            switch self {
            case .request:     return "Reset password"
            case .setPassword: return "Set new password"
            case .updated:     return "Password updated!"
            }
        }
    }

    enum FieldKey: String { case email, resetCode, password }

    let session: SessionManager

    var activeStep: Step = .request

    // Service
    var serviceURLText: String

    // Step 1
    var email: String

    // Step 2
    var resetCode: String = ""
    var password: String = ""

    // Submission state
    var isSubmitting = false
    var submitError: String?
    var fieldErrorKey: FieldKey?

    init(session: SessionManager, initialEmail: String) {
        self.session = session
        self.email = initialEmail
        self.serviceURLText = session.serviceURL.absoluteString
    }

    var serviceURL: URL? {
        let trimmed = serviceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        return url
    }

    func clearError() {
        submitError = nil
        fieldErrorKey = nil
    }

    // MARK: - Step 1: request reset

    func requestReset() async -> Bool {
        clearError()
        guard SignupValidation.isLikelyEmail(email) else {
            submitError = "Your email appears to be invalid."
            fieldErrorKey = .email
            return false
        }
        guard let url = serviceURL else {
            submitError = "Service URL is not valid."
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.requestPasswordReset(
                serviceURL: url,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            activeStep = .setPassword
            return true
        } catch ATError.xrpc(let code, let message) {
            submitError = message.isEmpty ? code : message
            fieldErrorKey = .email
            return false
        } catch ATError.network(let urlError) {
            submitError = "Unable to contact your service. \(urlError.localizedDescription)"
            return false
        } catch ATError.httpStatus(let status) {
            submitError = "Server error (\(status)). Check your hosting provider."
            return false
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    // MARK: - Step 2: set new password

    /// Validates and reformats the reset code, mutating `resetCode` to the
    /// canonical `XXXXX-XXXXX` form on success. Returns `false` and sets the
    /// error fields on failure. Mirrors RN `onBlur` in `SetNewPasswordForm`.
    @discardableResult
    func validateResetCode() -> Bool {
        guard let formatted = PasswordResetValidation.checkAndFormatResetCode(resetCode) else {
            submitError = "You have entered an invalid code. It should look like XXXXX-XXXXX."
            fieldErrorKey = .resetCode
            return false
        }
        resetCode = formatted
        return true
    }

    func setPassword() async -> Bool {
        clearError()
        guard let formatted = PasswordResetValidation.checkAndFormatResetCode(resetCode) else {
            submitError = "You have entered an invalid code. It should look like XXXXX-XXXXX."
            fieldErrorKey = .resetCode
            return false
        }
        resetCode = formatted

        guard !password.isEmpty else {
            submitError = "Please enter a password."
            fieldErrorKey = .password
            return false
        }
        guard password.count >= SignupValidation.minPasswordLength else {
            submitError = "Your password must be at least \(SignupValidation.minPasswordLength) characters long."
            fieldErrorKey = .password
            return false
        }
        guard let url = serviceURL else {
            submitError = "Service URL is not valid."
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.resetPassword(
                serviceURL: url,
                token: formatted,
                password: password
            )
            activeStep = .updated
            return true
        } catch ATError.xrpc(let code, let message) {
            submitError = message.isEmpty ? code : message
            // Distinguish bad-token (most common cause) from other failures.
            let lowered = (code + " " + message).lowercased()
            if lowered.contains("token") || lowered.contains("code") {
                fieldErrorKey = .resetCode
            }
            return false
        } catch ATError.network(let urlError) {
            submitError = "Unable to contact your service. \(urlError.localizedDescription)"
            return false
        } catch ATError.httpStatus(let status) {
            submitError = "Server error (\(status)). Check your hosting provider."
            return false
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    // MARK: - Navigation

    func goToRequestStep() {
        clearError()
        activeStep = .request
    }
}

// MARK: - Step 1: request reset

struct ForgotPasswordRequestView: View {

    @Bindable var model: ForgotPasswordModel
    let onCancel: () -> Void

    @State private var showCustomServer = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case service, email }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.submitError {
                SignupErrorBanner(message: error)
            }

            hostingProviderSection
            emailField

            Text("Enter the email you used to create your account. We'll send you a \"reset code\" so you can set a new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Already have a code?") {
                    model.clearError()
                    model.activeStep = .setPassword
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)

                Spacer()

                Button {
                    Task { _ = await model.requestReset() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Next")
                            .fontWeight(.semibold)
                        if model.isSubmitting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSubmitting)
            }
            .padding(.top, 24)
        }
    }

    private var hostingProviderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hosting provider")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                if showCustomServer {
                    TextField("https://bsky.social", text: $model.serviceURLText)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .service)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .keyboardType(.URL)
#endif
                } else {
                    Text(displayServiceName)
                        .font(.subheadline)
                }
                Spacer()
                Button(showCustomServer ? "Done" : "Change") {
                    withAnimation { showCustomServer.toggle() }
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var displayServiceName: String {
        URL(string: model.serviceURLText)?.host ?? model.serviceURLText
    }

    private var emailField: some View {
        labeledField(
            label: "Email address",
            isInvalid: model.fieldErrorKey == .email,
            iconSystemName: "at"
        ) {
            TextField("Enter your email address", text: $model.email)
                .textFieldStyle(.plain)
                .focused($focus, equals: .email)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { _ = await model.requestReset() } }
#if os(iOS)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
#endif
        }
    }

    private func labeledField<Content: View>(
        label: String,
        isInvalid: Bool,
        iconSystemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: iconSystemName)
                    .foregroundStyle(.secondary)
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isInvalid ? Color.red : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Step 2: set new password

struct ForgotPasswordSetView: View {

    @Bindable var model: ForgotPasswordModel

    @FocusState private var focus: Field?

    private enum Field: Hashable { case code, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You will receive an email with a \"reset code.\" Enter that code here, then enter your new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = model.submitError {
                SignupErrorBanner(message: error)
            }

            resetCodeField
            passwordField

            HStack {
                Button("Back") {
                    model.goToRequestStep()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { _ = await model.setPassword() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Next")
                            .fontWeight(.semibold)
                        if model.isSubmitting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSubmitting)
            }
            .padding(.top, 24)
        }
    }

    private var resetCodeField: some View {
        labeledField(
            label: "Reset code",
            isInvalid: model.fieldErrorKey == .resetCode,
            iconSystemName: "ticket"
        ) {
            TextField("Looks like XXXXX-XXXXX", text: $model.resetCode)
                .textFieldStyle(.plain)
                .focused($focus, equals: .code)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
                .onChange(of: focus) { _, newValue in
                    // Mirror RN `onBlur`: when the field loses focus, validate
                    // and reformat. RN also clears the error when the field is
                    // refocused.
                    if newValue == .code {
                        model.clearError()
                    } else if newValue != nil, !model.resetCode.isEmpty {
                        _ = model.validateResetCode()
                    }
                }
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
        }
    }

    private var passwordField: some View {
        labeledField(
            label: "New password",
            isInvalid: model.fieldErrorKey == .password,
            iconSystemName: "lock"
        ) {
            SecureField("Enter a password", text: $model.password)
                .textFieldStyle(.plain)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { _ = await model.setPassword() } }
#if os(iOS)
                .textContentType(.newPassword)
#endif
        }
    }

    private func labeledField<Content: View>(
        label: String,
        isInvalid: Bool,
        iconSystemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: iconSystemName)
                    .foregroundStyle(.secondary)
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isInvalid ? Color.red : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Step 3: confirmation

struct ForgotPasswordUpdatedView: View {

    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .padding(.top, 32)

            Text("Password updated!")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: onSignIn) {
                Text("Sign in now")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("Forgot Password — Light") {
    ForgotPasswordFlowView(
        session: SessionManager(accountStore: PreviewAccountStore(), network: PreviewNetworkClient()),
        onCompleted: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Forgot Password — Dark") {
    ForgotPasswordFlowView(
        session: SessionManager(accountStore: PreviewAccountStore(), network: PreviewNetworkClient()),
        onCompleted: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
