import SwiftUI
import BlueskyUI

struct OnboardingProfileStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        let account = model.session.currentAccount
        return VStack(alignment: .leading, spacing: 20) {
            // Avatar circle — placeholder for now. RN drops the user into the
            // PHPicker (or a generated avatar dialog); we render the initials
            // placeholder via `AvatarView` and call out the limitation.
            HStack {
                Spacer()
                AvatarView(
                    url: account?.avatarURL,
                    handle: account?.handle.rawValue ?? "?",
                    size: 96
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(theme.colors.link)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 4, y: 4)
                }
                Spacer()
            }
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Display name")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                TextField("Your name", text: $model.displayName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.colors.backgroundSecondary)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.colors.border, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                TextEditor(text: $model.bio)
                    .frame(minHeight: 90)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.colors.backgroundSecondary)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.colors.border, lineWidth: 1)
                    }
                Text("\(280 - model.bio.count) characters remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer(minLength: 8)

            OnboardingPrimaryButton("Continue") {
                model.goNext()
            }
        }
    }
}
