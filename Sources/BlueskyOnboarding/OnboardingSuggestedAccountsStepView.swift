import SwiftUI
import BlueskyCore
import BlueskyUI

struct OnboardingSuggestedAccountsStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            interestTabBar

            Group {
                if model.isLoadingSuggestions {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                            .padding(.vertical, 40)
                        Spacer()
                    }
                } else if let err = model.suggestionsError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(err)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.error)
                        Button("Retry") {
                            Task { await model.loadSuggestedAccounts(category: model.selectedInterestTab) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 16)
                } else if model.suggestedActors.isEmpty {
                    Text("No suggestions available right now. You can always follow more accounts later.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.suggestedActors.enumerated()), id: \.element.did) { index, actor in
                            OnboardingProfileRow(actor: actor, model: model)
                            if index < model.suggestedActors.count - 1 {
                                Divider()
                                    .background(theme.colors.borderSubtle)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.colors.backgroundSecondary)
                    )
                }
            }

            Spacer(minLength: 8)

            OnboardingPrimaryButton("Continue") {
                model.goNext()
            }
        }
        .task {
            // Initial load when the step appears. Re-runs only when the
            // selected interest tab changes (`.task(id:)` below handles that).
            if model.suggestedActors.isEmpty {
                await model.loadSuggestedAccounts(category: model.selectedInterestTab)
            }
        }
        .task(id: model.selectedInterestTab) {
            // Skip the duplicate call on initial mount — only re-fetch when the
            // user actively switches tabs.
            if !model.suggestedActors.isEmpty || model.selectedInterestTab != nil {
                await model.loadSuggestedAccounts(category: model.selectedInterestTab)
            }
        }
    }

    /// Horizontal scrollable tab strip — the user's selected interests come
    /// first (bias), followed by an "All" pill that maps to a `nil` category.
    /// Matches the visual ordering RN uses in `StepSuggestedAccounts`.
    @ViewBuilder
    private var interestTabBar: some View {
        let tabs: [(id: String?, label: String)] = {
            var rows: [(id: String?, label: String)] = [(nil, "All")]
            for tag in model.selectedInterests.sorted() {
                rows.append((tag, OnboardingInterests.displayName(for: tag)))
            }
            return rows
        }()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.label) { tab in
                    let isSelected = model.selectedInterestTab == tab.id
                    Button {
                        model.selectedInterestTab = tab.id
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : theme.colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(isSelected ? theme.colors.link : theme.colors.backgroundSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Profile row

private struct OnboardingProfileRow: View {
    let actor: ProfileView
    @Bindable var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                url: actor.avatar,
                handle: actor.handle.rawValue,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(actor.displayName ?? actor.handle.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Text("@\(actor.handle.rawValue)")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                if let desc = actor.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            followButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var followButton: some View {
        let isFollowing = model.followedDIDs.contains(actor.did.rawValue)
            || actor.viewer?.following != nil
        Button {
            Task { await model.toggleFollow(actor) }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFollowing ? theme.colors.textPrimary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isFollowing ? theme.colors.backgroundSecondary : theme.colors.link)
                )
                .overlay {
                    if isFollowing {
                        Capsule().stroke(theme.colors.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFollowing)
    }
}
