import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyAuth
import BlueskyUI

/// Multi-step post-signup onboarding flow.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Onboarding/index.tsx`:
/// `welcome → profile → interests → suggested-accounts → finished`. The
/// suggested-feeds, suggested-starter-packs and find-contacts steps that
/// RN shows are deferred — see issue #0092 Notes.
public struct OnboardingFlowView: View {

    @State private var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    private let onComplete: () -> Void

    public init(
        session: SessionManager,
        network: any NetworkClient,
        accountStore: any AccountStore,
        preferences: any PreferencesStore,
        onComplete: @escaping () -> Void
    ) {
        _model = State(initialValue: OnboardingModel(
            session: session,
            network: network,
            accountStore: accountStore,
            preferences: preferences
        ))
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        switch model.activeStep {
                        case .welcome:
                            OnboardingWelcomeStepView(model: model)
                        case .profile:
                            OnboardingProfileStepView(model: model)
                        case .interests:
                            OnboardingInterestsStepView(model: model)
                        case .suggestedAccounts:
                            OnboardingSuggestedAccountsStepView(model: model)
                        case .finished:
                            OnboardingFinishedStepView(model: model, onComplete: onComplete)
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: model.activeStep)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                if model.canGoBack {
                    Button {
                        model.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Spacer().frame(width: 32, height: 32)
                }

                stepDots

                Spacer().frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.activeStep.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.colors.textPrimary)
                if let subtitle = model.activeStep.subtitle {
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Step indicator: a row of small dots, one per displayed step. Mirrors RN's
    /// `OnboardingPosition` (a 0-indexed pill counter); we use dots since the
    /// SwiftUI flow has fewer total steps than the RN flow.
    @ViewBuilder
    private var stepDots: some View {
        let total = model.totalDisplayedSteps
        let active = min(model.activeStep.rawValue, total - 1)
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= active ? theme.colors.link : theme.colors.border)
                    .frame(width: index == active ? 18 : 8, height: 6)
                    .animation(.easeOut(duration: 0.2), value: active)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel("Step \(active + 1) of \(total)")
    }
}

// MARK: - Reusable controls

struct OnboardingPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.blueskyTheme) private var theme

    init(
        _ title: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDisabled ? theme.colors.textTertiary : theme.colors.link)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(theme.colors.link)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.colors.link.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}
