import SwiftUI
import BlueskyCore

/// A small "verified account" check, rendered next to a display name.
///
/// Mirrors Bluesky's verified-account treatment: a filled blue check
/// (`checkmark.seal.fill`) when the account is verified by a trusted verifier.
/// Currently we render the same glyph for both the regular `verified` and
/// `verifier` roles — RN distinguishes them with a scalloped variant, which
/// is left as a follow-up if needed.
///
/// The badge owns its own a11y label so the surrounding text can stay clean
/// (display-name → handle, no extra wording).
public struct VerifiedBadge: View {

    /// Display size in points. Defaults to 14 — sized to sit comfortably next
    /// to a body-headline display name without dominating it.
    public let size: CGFloat

    @Environment(\.blueskyTheme) private var theme

    public init(size: CGFloat = 14) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(theme.colors.link)
            .accessibilityLabel("Verified")
    }
}

/// Convenience: returns a `VerifiedBadge` only when the profile's verification
/// state warrants it. Returning a `View?` keeps call sites a one-liner:
///
/// ```swift
/// if let badge = VerifiedBadge.forProfile(author) { badge }
/// ```
public extension VerifiedBadge {
    /// `VerifiedBadge` if `profile.verification?.isVerified == true`, else `nil`.
    static func forProfile(_ profile: ProfileBasic, size: CGFloat = 14) -> VerifiedBadge? {
        guard profile.verification?.isVerified == true else { return nil }
        return VerifiedBadge(size: size)
    }
}

// MARK: - Previews

#Preview("VerifiedBadge — Light") {
    HStack(spacing: 8) {
        Text("NBA")
            .font(Typography.headline)
        VerifiedBadge()
    }
    .padding()
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("VerifiedBadge — Dark") {
    HStack(spacing: 8) {
        Text("NBA")
            .font(Typography.headline)
            .foregroundStyle(BlueskyTheme.dark.colors.textPrimary)
        VerifiedBadge()
    }
    .padding()
    .background(BlueskyTheme.dark.colors.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
