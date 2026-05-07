import SwiftUI
import BlueskyCore

/// Step 2 of the signup flow: handle entry with live validation, suffix preview,
/// and a debounced availability check against the chosen PDS. Mirrors
/// `Bluesky-ReactNative/src/screens/Signup/StepHandle`.
struct SignupStepHandleView: View {

    @Bindable var model: SignupModel

    @FocusState private var focused: Bool
    @State private var availability: Availability = .idle
    @State private var checkTask: Task<Void, Never>?

    private enum Availability: Equatable {
        case idle, checking, available, unavailable, networkError
    }

    private var check: SignupValidation.HandleCheck {
        model.handleCheck
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.submitError {
                SignupErrorBanner(message: error)
            }

            handleField

            requirements

            SignupBackNextButtons(
                backTitle: "Back",
                nextTitle: model.requiresCaptcha ? "Next" : "Create account",
                isLoading: model.isSubmitting,
                isNextDisabled: !canProceed,
                onBack: { model.goBack() },
                onNext: { Task { await handleNext() } }
            )
        }
        .onAppear { focused = true }
        .onChange(of: model.handle) { _, newValue in
            scheduleAvailabilityCheck(for: newValue)
        }
    }

    // MARK: - Subviews

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Username")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "at")
                    .foregroundStyle(.secondary)
                TextField("yourname", text: Binding(
                    get: { model.handle },
                    set: { model.handle = $0.lowercased() }
                ))
                .textFieldStyle(.plain)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await handleNext() } }
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                if !model.handle.isEmpty {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                trailingStatusIcon
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )

            if !model.handle.isEmpty {
                Text("Your handle will be \(model.fullHandlePreview)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var trailingStatusIcon: some View {
        switch availability {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .idle, .networkError:
            EmptyView()
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !check.isEmpty {
                if !check.handleChars {
                    requirementText("Username must only contain letters (a-z), numbers, and hyphens", ok: false)
                }
                if !check.hyphenStartOrEnd {
                    requirementText("Username cannot begin or end with a hyphen", ok: false)
                }
                if !check.frontLengthNotTooLong {
                    requirementText("Username cannot be longer than \(SignupValidation.maxFrontHandleLength) characters", ok: false)
                }
                if availability == .unavailable {
                    requirementText("\(model.fullHandlePreview) is not available", ok: false)
                }
            }
        }
    }

    private func requirementText(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
                .font(.caption)
            Text(text)
                .font(.footnote)
                .foregroundStyle(ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
        }
    }

    // MARK: - Computed

    private var suffix: String {
        let domain = model.userDomain
        return domain.hasPrefix(".") ? domain : ".\(domain)"
    }

    private var borderColor: Color {
        if availability == .unavailable { return .red }
        if !check.overall && !model.handle.isEmpty { return .red }
        if availability == .available { return .green.opacity(0.6) }
        return .clear
    }

    private var canProceed: Bool {
        check.overall && availability != .unavailable && !model.isSubmitting
    }

    // MARK: - Availability

    private func scheduleAvailabilityCheck(for raw: String) {
        checkTask?.cancel()
        availability = .idle
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard check.overall, !value.isEmpty else { return }

        let full = SignupValidation.createFullHandle(value, model.userDomain)
        let session = model.session
        let serviceURL = model.serviceURL ?? URL(string: "https://bsky.social")!

        checkTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            availability = .checking
            do {
                let available = try await checkHandleAvailability(handle: full, serviceURL: serviceURL)
                if Task.isCancelled { return }
                availability = available ? .available : .unavailable
            } catch {
                if !Task.isCancelled {
                    availability = .networkError
                }
            }
            _ = session // silence unused warning
        }
    }

    /// Looks up `com.atproto.identity.resolveHandle`. A successful response
    /// means the handle is taken; a 400 / `InvalidHandle` means it's free.
    private func checkHandleAvailability(handle: String, serviceURL: URL) async throws -> Bool {
        let url = serviceURL
            .appending(path: "xrpc/com.atproto.identity.resolveHandle")
            .appending(queryItems: [URLQueryItem(name: "handle", value: handle)])
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if (200..<300).contains(http.statusCode) {
                return false // resolved -> taken
            }
            if http.statusCode == 400 {
                return true // unresolved -> available
            }
        }
        return true
    }

    private func handleNext() async {
        guard check.overall else { return }
        if availability == .unavailable { return }
        if model.requiresCaptcha {
            model.goNext()
        } else {
            // Skip captcha and submit directly when the PDS doesn't require it.
            let ok = await model.submit()
            if !ok { return }
        }
    }
}
