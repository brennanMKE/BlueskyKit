import SwiftUI

/// A circular progress ring used by the composer to show how many characters
/// remain before the post-length cap.
///
/// Mirrors the React Native composer's `CharProgress` component
/// (`Bluesky-ReactNative/src/view/com/composer/char-progress/CharProgress.tsx`)
/// — same 30pt size, same color thresholds, same "show numeric remaining only
/// when ≤ 20 chars left or over the cap" behavior.
///
/// **Color states** (based on `progress = count / max`):
/// - `progress < 0.93` → primary blue (`theme.colors.link`).
/// - `0.93 ≤ progress ≤ 1.0` (last 20 chars or fewer remaining) → amber.
/// - `progress > 1.0` (over the cap) → red (`theme.colors.error`).
///
/// **Numeric display.** When more than 20 characters remain the ring renders
/// just the fill — no number — matching RN. Once within 20 of the cap (or
/// past it) the remaining count appears beside the ring (negative when over).
public struct CharProgressRing: View {

    private let count: Int
    private let max: Int
    private let size: CGFloat

    @Environment(\.blueskyTheme) private var theme

    public init(count: Int, max: Int = 300, size: CGFloat = 24) {
        self.count = count
        self.max = max
        self.size = size
    }

    /// Raw progress; can exceed 1.0 when the user has typed past the cap.
    private var progress: Double {
        guard max > 0 else { return 0 }
        return Double(count) / Double(max)
    }

    /// Clamped progress for the foreground stroke trim — the ring tops out
    /// visually at full at 100% and stays full while over.
    private var clampedProgress: Double {
        Swift.min(Swift.max(progress, 0), 1)
    }

    private var remaining: Int { max - count }

    /// Show the numeric remaining count once we're within the warning band
    /// or over the cap. Mirrors RN: the bare ring is shown until the user is
    /// in the last 20 characters.
    private var showsNumeric: Bool {
        remaining <= 20
    }

    private var ringColor: Color {
        if progress > 1.0 {
            return theme.colors.error
        }
        if progress >= 0.93 {
            // Amber / warning band — `BlueskyTheme.Colors` doesn't define a
            // dedicated warning token yet, so fall back to a tuned orange that
            // reads on light, dark, and dim surfaces.
            return Color.orange
        }
        return theme.colors.link
    }

    private var trackColor: Color {
        theme.colors.border
    }

    private var numericColor: Color {
        progress > 1.0 ? theme.colors.error : theme.colors.textSecondary
    }

    public var body: some View {
        HStack(spacing: 6) {
            if showsNumeric {
                Text("\(remaining)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(numericColor)
                    .accessibilityHidden(true)
            }

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: 2)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: clampedProgress)
                    .animation(.smooth, value: ringColor)
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Characters")
        .accessibilityValue("\(remaining) remaining of \(max)")
    }
}

// MARK: - Previews

#Preview("CharProgressRing — Light") {
    VStack(alignment: .leading, spacing: 16) {
        CharProgressRing(count: 0)
        CharProgressRing(count: 150)
        CharProgressRing(count: 279)   // boundary (~93%)
        CharProgressRing(count: 285)   // amber
        CharProgressRing(count: 300)   // at cap
        CharProgressRing(count: 312)   // over
    }
    .padding()
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("CharProgressRing — Dark") {
    VStack(alignment: .leading, spacing: 16) {
        CharProgressRing(count: 0)
        CharProgressRing(count: 150)
        CharProgressRing(count: 279)
        CharProgressRing(count: 285)
        CharProgressRing(count: 300)
        CharProgressRing(count: 312)
    }
    .padding()
    .background(BlueskyTheme.dark.colors.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}

#Preview("CharProgressRing — Dim") {
    VStack(alignment: .leading, spacing: 16) {
        CharProgressRing(count: 0)
        CharProgressRing(count: 150)
        CharProgressRing(count: 279)
        CharProgressRing(count: 285)
        CharProgressRing(count: 300)
        CharProgressRing(count: 312)
    }
    .padding()
    .background(BlueskyTheme.dim.colors.background)
    .blueskyTheme(.dim)
    .preferredColorScheme(.dark)
}
