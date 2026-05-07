import SwiftUI
import BlueskyUI

struct OnboardingFinishedStepView: View {
    @Bindable var model: OnboardingModel
    let onComplete: () -> Void

    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Big checkmark celebration. RN uses a card pager for the
            // "value proposition"; the simplified parity port renders a
            // single page with the same gist.
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(theme.colors.success)
                Spacer()
            }
            .padding(.vertical, 12)

            Text("Welcome to Bluesky")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Your account is ready. Tap below to start exploring your home feed.")
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if let err = model.finishingError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.error)
            }

            Spacer(minLength: 16)

            OnboardingPrimaryButton(
                model.isFinishing ? "Setting up…" : "Take me to Bluesky",
                isLoading: model.isFinishing
            ) {
                Task {
                    let ok = await model.finish()
                    if ok { onComplete() }
                }
            }
        }
    }
}
