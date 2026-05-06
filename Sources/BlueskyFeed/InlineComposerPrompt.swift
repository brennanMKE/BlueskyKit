import SwiftUI
import BlueskyCore
import BlueskyUI

#if os(iOS)

/// Inline "What's up?" composer entry point pinned to the top of the iOS Home
/// feed list, sitting just below the tab strip.
///
/// Mirrors the React Native reference layout (#0075):
/// - Leading: 24pt circular avatar of the signed-in viewer (initials fallback).
/// - Center: "What's up?" prompt in the secondary text color, left-aligned.
/// - Trailing: outlined `camera` and `photo` icon buttons.
///
/// Tapping anywhere on the row, or either icon button, opens `ComposerSheet`.
/// The icon buttons additionally pre-prime the picker via the parent's
/// `onCamera` / `onPhotoLibrary` callbacks; the bare row reports `.none`.
///
/// This view is iOS-only. macOS uses the toolbar compose action and does not
/// render the inline prompt.
struct InlineComposerPrompt: View {

    @Environment(\.blueskyTheme) private var theme

    /// Avatar URL for the signed-in viewer, or `nil` while loading / unknown
    /// (the avatar falls back to the initials placeholder rendered by
    /// `AvatarView`).
    let avatarURL: URL?
    /// Handle to seed the initials placeholder when no avatar URL is available.
    let handle: String
    /// Tap on the bare row — opens the composer with no primed picker.
    let onTap: () -> Void
    /// Tap on the camera icon — opens the composer primed for camera capture.
    let onCamera: () -> Void
    /// Tap on the photo icon — opens the composer primed for the Photos picker.
    let onPhotoLibrary: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(url: avatarURL, handle: handle, size: 24)

                Text("What's up?")
                    .font(.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    iconButton(systemName: "camera", action: onCamera)
                    iconButton(systemName: "photo", action: onPhotoLibrary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Outlined circular icon button used for both camera and photo actions.
    /// The wrapping row already handles the row-level tap; using a `Button`
    /// here lets the trailing icons consume their own taps without bubbling
    /// up to the row's `onTap` and double-firing.
    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(theme.colors.border, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("InlineComposerPrompt — Light") {
    VStack(spacing: 0) {
        InlineComposerPrompt(
            avatarURL: nil,
            handle: "alice.bsky.social",
            onTap: {},
            onCamera: {},
            onPhotoLibrary: {}
        )
        Divider()
    }
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("InlineComposerPrompt — Dark") {
    VStack(spacing: 0) {
        InlineComposerPrompt(
            avatarURL: nil,
            handle: "alice.bsky.social",
            onTap: {},
            onCamera: {},
            onPhotoLibrary: {}
        )
        Divider()
    }
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}

#endif
