import SwiftUI
import BlueskyUI

struct OnboardingWelcomeStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Three short value-prop bullets — short enough to skim, mirrors
            // RN's `ValuePropositionPager` content (just rendered statically
            // here instead of paged).
            valueProp(
                systemImage: "person.2.fill",
                title: "Follow your interests",
                body: "Build a feed by picking topics and following accounts."
            )
            valueProp(
                systemImage: "bubble.left.and.bubble.right.fill",
                title: "Join the conversation",
                body: "Reply, repost, and quote-post to engage with anyone."
            )
            valueProp(
                systemImage: "sparkles",
                title: "Discover new feeds",
                body: "Choose from custom feeds curated by the community."
            )

            Spacer(minLength: 16)

            OnboardingPrimaryButton("Get started") {
                model.goNext()
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func valueProp(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.colors.link)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(theme.colors.link.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}
