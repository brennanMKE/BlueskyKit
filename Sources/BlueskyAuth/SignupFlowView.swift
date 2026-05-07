import SwiftUI
import BlueskyCore
import BlueskyKit

/// Three-step signup flow that mirrors the React Native client (`screens/Signup`):
///
/// 1. **Info**     hosting provider, optional invite code, email, password, birthdate.
/// 2. **Handle**   handle picker with availability check and suffix preview.
/// 3. **Captcha**  hCaptcha gate served from the PDS, shown in a `WKWebView`.
///
/// On a successful `com.atproto.server.createAccount` the new session is saved
/// via `SessionManager` exactly like login.
public struct SignupFlowView: View {

    private let session: SessionManager
    private let onSuccess: () -> Void
    private let onCancel: () -> Void

    @State private var model: SignupModel

    public init(session: SessionManager, onSuccess: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        _model = State(initialValue: SignupModel(session: session))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader

                Group {
                    switch model.activeStep {
                    case .info:
                        SignupStepInfoView(model: model, onCancel: onCancel)
                    case .handle:
                        SignupStepHandleView(model: model)
                    case .captcha:
                        SignupStepCaptchaView(model: model, onSuccess: onSuccess)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await model.loadServiceDescription() }
        .animation(.easeInOut(duration: 0.18), value: model.activeStep)
        .navigationTitle("Create account")
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(model.activeStep.rawValue + 1) of \(model.totalStepCount)")
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
final class SignupModel {
    enum Step: Int, CaseIterable {
        case info, handle, captcha
        var title: String {
            switch self {
            case .info:    return "Your account"
            case .handle:  return "Choose your username"
            case .captcha: return "Complete the challenge"
            }
        }
    }

    let session: SessionManager

    var activeStep: Step = .info

    // Service
    var serviceURLText: String = "https://bsky.social"
    var serviceDescription: DescribeServerResponse?
    var isFetchingService = false
    var serviceError: String?

    // Step 1 fields
    var inviteCode: String = ""
    var email: String = ""
    var password: String = ""
    var dateOfBirth: Date = {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    }()

    // Step 2 fields
    var handle: String = ""

    // Step 3 fields
    var verificationCode: String?

    // Submission state
    var isSubmitting = false
    var submitError: String?
    var fieldErrorKey: FieldKey?

    enum FieldKey: String { case inviteCode, email, password, dateOfBirth, handle }

    init(session: SessionManager) {
        self.session = session
        self.serviceURLText = session.serviceURL.absoluteString
    }

    var serviceURL: URL? {
        let trimmed = serviceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        return url
    }

    var userDomain: String {
        serviceDescription?.availableUserDomains.first ?? ".bsky.social"
    }

    var requiresInviteCode: Bool {
        serviceDescription?.inviteCodeRequired ?? false
    }

    var requiresCaptcha: Bool {
        serviceDescription?.phoneVerificationRequired ?? true
    }

    var totalStepCount: Int {
        requiresCaptcha ? 3 : 2
    }

    func loadServiceDescription() async {
        guard let url = serviceURL else {
            serviceError = "Service URL is not valid."
            return
        }
        isFetchingService = true
        serviceError = nil
        defer { isFetchingService = false }
        do {
            serviceDescription = try await session.describeServer(url)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func clearFieldError() {
        submitError = nil
        fieldErrorKey = nil
    }

    // MARK: - Navigation

    func goNext() {
        guard let next = Step(rawValue: activeStep.rawValue + 1) else { return }
        clearFieldError()
        activeStep = next
    }

    func goBack() {
        guard let prev = Step(rawValue: activeStep.rawValue - 1) else { return }
        clearFieldError()
        activeStep = prev
    }

    // MARK: - Step 1 validation

    func validateInfoStep() -> Bool {
        clearFieldError()
        if requiresInviteCode && inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitError = "Please enter your invite code."
            fieldErrorKey = .inviteCode
            return false
        }
        if !SignupValidation.isLikelyEmail(email) {
            submitError = "Your email appears to be invalid."
            fieldErrorKey = .email
            return false
        }
        if password.count < SignupValidation.minPasswordLength {
            submitError = "Your password must be at least 8 characters long."
            fieldErrorKey = .password
            return false
        }
        if !SignupValidation.isOverAge(dateOfBirth) {
            submitError = "You must be at least \(SignupValidation.minSignupAge) years old to create an account."
            fieldErrorKey = .dateOfBirth
            return false
        }
        return true
    }

    // MARK: - Step 2 validation

    var handleCheck: SignupValidation.HandleCheck {
        SignupValidation.validateServiceHandle(handle, userDomain)
    }

    var fullHandlePreview: String {
        SignupValidation.createFullHandle(handle, userDomain)
    }

    // MARK: - Submit

    func submit() async -> Bool {
        guard let url = serviceURL else {
            submitError = "Service URL is not valid."
            return false
        }
        if requiresCaptcha && (verificationCode?.isEmpty ?? true) {
            submitError = "Please complete the captcha to continue."
            return false
        }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let request = CreateAccountRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            handle: SignupValidation.createFullHandle(handle, userDomain),
            password: password,
            inviteCode: requiresInviteCode ? inviteCode.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            verificationCode: verificationCode,
            verificationPhone: nil
        )

        do {
            _ = try await session.createAccount(
                request: request,
                serviceURL: url,
                birthDate: dateOfBirth,
                email: request.email
            )
            return true
        } catch ATError.xrpc(let code, let message) {
            // Surface invite-code errors on Step 1, handle errors on Step 2.
            let lowered = (code + " " + message).lowercased()
            if lowered.contains("invite") {
                fieldErrorKey = .inviteCode
                activeStep = .info
            } else if lowered.contains("handle") || lowered.contains("username") {
                fieldErrorKey = .handle
                activeStep = .handle
            }
            submitError = message.isEmpty ? code : message
            return false
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }
}

// MARK: - Shared chrome

struct SignupBackNextButtons: View {
    let backTitle: String
    let nextTitle: String
    let isLoading: Bool
    let isNextDisabled: Bool
    let hideNext: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    init(
        backTitle: String = "Back",
        nextTitle: String = "Next",
        isLoading: Bool = false,
        isNextDisabled: Bool = false,
        hideNext: Bool = false,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void = {}
    ) {
        self.backTitle = backTitle
        self.nextTitle = nextTitle
        self.isLoading = isLoading
        self.isNextDisabled = isNextDisabled
        self.hideNext = hideNext
        self.onBack = onBack
        self.onNext = onNext
    }

    var body: some View {
        HStack {
            Button(action: onBack) {
                Text(backTitle)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)

            Spacer()

            if !hideNext {
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text(nextTitle)
                            .fontWeight(.semibold)
                        if isLoading {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isNextDisabled)
            }
        }
        .padding(.top, 24)
    }
}

struct SignupErrorBanner: View {
    let message: String
    var body: some View {
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

#Preview("Signup — Light") {
    SignupFlowView(
        session: SessionManager(accountStore: PreviewAccountStore(), network: PreviewNetworkClient()),
        onSuccess: {},
        onCancel: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Signup — Dark") {
    SignupFlowView(
        session: SessionManager(accountStore: PreviewAccountStore(), network: PreviewNetworkClient()),
        onSuccess: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
