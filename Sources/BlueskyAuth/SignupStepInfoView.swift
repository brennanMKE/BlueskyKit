import SwiftUI
import BlueskyCore

/// Step 1 of the signup flow: hosting provider, optional invite code, email,
/// password, birthdate. Mirrors `Bluesky-ReactNative/src/screens/Signup/StepInfo`.
struct SignupStepInfoView: View {

    @Bindable var model: SignupModel
    let onCancel: () -> Void

    @State private var showCustomServer = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case service, invite, email, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.submitError {
                SignupErrorBanner(message: error)
            }

            hostingProviderSection

            if model.isFetchingService {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Contacting hosting provider…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let serviceErr = model.serviceError {
                SignupErrorBanner(message: serviceErr)
                Button {
                    Task { await model.loadServiceDescription() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else if model.serviceDescription != nil {
                if model.requiresInviteCode {
                    inviteCodeField
                }
                emailField
                passwordField
                birthdateField
            }

            SignupBackNextButtons(
                backTitle: "Cancel",
                nextTitle: "Next",
                isLoading: model.isFetchingService,
                isNextDisabled: model.serviceDescription == nil,
                onBack: onCancel,
                onNext: handleNext
            )
        }
    }

    // MARK: - Subviews

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
                        .onSubmit { Task { await model.loadServiceDescription() } }
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
                    if showCustomServer {
                        Task { await model.loadServiceDescription() }
                    }
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

    private var inviteCodeField: some View {
        labeledField(
            label: "Invite code",
            isInvalid: model.fieldErrorKey == .inviteCode,
            iconSystemName: "ticket"
        ) {
            TextField("Required for this provider", text: $model.inviteCode)
                .textFieldStyle(.plain)
                .focused($focus, equals: .invite)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .email }
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
        }
    }

    private var emailField: some View {
        labeledField(
            label: "Email",
            isInvalid: model.fieldErrorKey == .email,
            iconSystemName: "envelope"
        ) {
            TextField("you@example.com", text: $model.email)
                .textFieldStyle(.plain)
                .focused($focus, equals: .email)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
#if os(iOS)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
#endif
        }
    }

    private var passwordField: some View {
        labeledField(
            label: "Password",
            isInvalid: model.fieldErrorKey == .password,
            iconSystemName: "lock"
        ) {
            SecureField("At least 8 characters", text: $model.password)
                .textFieldStyle(.plain)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(handleNext)
#if os(iOS)
                .textContentType(.newPassword)
#endif
        }
    }

    private var birthdateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your birth date")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            DatePicker(
                "Birth date",
                selection: $model.dateOfBirth,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(model.fieldErrorKey == .dateOfBirth ? Color.red : Color.clear, lineWidth: 1)
                    )
            )
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

    // MARK: - Actions

    private func handleNext() {
        guard model.validateInfoStep() else { return }
        model.goNext()
    }
}
