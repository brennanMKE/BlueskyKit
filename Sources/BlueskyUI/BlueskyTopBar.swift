import SwiftUI

// MARK: - BlueskyTopBar

/// Slim, fixed top bar matching the Bluesky React Native app's mobile layout.
///
/// Sits flush below the status bar with three slots — leading, centered, and
/// trailing — so screens can supply their own actions (hamburger / brand /
/// hash on Home; a back button / title / overflow on a profile screen, etc.).
///
/// The bar is intentionally lightweight: a fixed-height `HStack` with a
/// theme-coloured background and a single-pixel bottom hairline. Use it from
/// the screen body, typically wrapped in a `VStack(spacing: 0)` above the
/// scrollable content. Callers are responsible for hiding the system
/// navigation bar (`.toolbar(.hidden, for: .navigationBar)`) when this top
/// bar replaces it.
public struct BlueskyTopBar<Leading: View, Center: View, Trailing: View>: View {

    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    @Environment(\.blueskyTheme) private var theme

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: BlueskyTopBar.slotWidth, height: BlueskyTopBar.height)
            Spacer(minLength: 0)
            center
                .frame(maxWidth: .infinity)
                .frame(height: BlueskyTopBar.height)
            Spacer(minLength: 0)
            trailing
                .frame(width: BlueskyTopBar.slotWidth, height: BlueskyTopBar.height)
        }
        .frame(height: BlueskyTopBar.height)
        .padding(.horizontal, 4)
        // Fix #0088: extend the bar's background behind the top safe area so
        // the iOS status bar sits over the chrome's color rather than over a
        // black band. The bar's *content* (the HStack above) keeps its 44pt
        // height inside the safe area; only the background fill bleeds up.
        // `ignoresSafeArea(edges: .top)` is a no-op when the view isn't at
        // the screen's top edge, so this is safe to leave on regardless of
        // where the bar is mounted.
        .background(
            theme.colors.background
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .top)
        )
    }

    /// Standard slim height (~44pt) — matches a UIKit nav bar so the visual
    /// weight is identical to the original system chrome it replaces.
    public static var height: CGFloat { 44 }

    /// Width allotted to each side slot. Wide enough for a 44pt tap target,
    /// narrow enough to leave the centre slot dominant.
    public static var slotWidth: CGFloat { 56 }
}

// MARK: - BlueskyWordmark

/// Centered text wordmark used on the top bar.
///
/// Defaults to "Bluesky" rendered in a heavy weight close to the brand wordmark
/// without infringing on the registered butterfly logo. Pass a custom string
/// (e.g. "Home", "Notifications") to reuse the same visual treatment for other
/// screen titles.
public struct BlueskyWordmark: View {

    let text: String
    let size: CGFloat

    @Environment(\.blueskyTheme) private var theme

    public init(_ text: String = "Bluesky", size: CGFloat = 20) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .default))
            .foregroundStyle(theme.colors.link)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - BlueskyTopBarIconButton

/// Square icon button sized to fit a `BlueskyTopBar` slot.
///
/// Renders a single SF Symbol with the secondary text colour and a 44pt tap
/// target. Use as the leading or trailing slot in `BlueskyTopBar` so the
/// pixel weight matches the wordmark in the centre.
public struct BlueskyTopBarIconButton: View {

    let systemImage: String
    let action: () -> Void
    let accessibilityLabel: String

    @Environment(\.blueskyTheme) private var theme

    public init(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Convenience initialisers

public extension BlueskyTopBar where Center == BlueskyWordmark {

    /// Convenience initialiser that uses the default `BlueskyWordmark`
    /// ("Bluesky") in the centre slot. Most Home-style top bars only need
    /// custom leading and trailing actions, so this saves the boilerplate.
    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            leading: leading,
            center: { BlueskyWordmark() },
            trailing: trailing
        )
    }
}

// MARK: - Previews

#Preview("BlueskyTopBar — Light") {
    VStack(spacing: 0) {
        BlueskyTopBar(
            leading: {
                BlueskyTopBarIconButton(
                    systemImage: "line.3.horizontal",
                    accessibilityLabel: "Open menu",
                    action: {}
                )
            },
            trailing: {
                BlueskyTopBarIconButton(
                    systemImage: "number",
                    accessibilityLabel: "My feeds",
                    action: {}
                )
            }
        )
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("BlueskyTopBar — Dark") {
    VStack(spacing: 0) {
        BlueskyTopBar(
            leading: {
                BlueskyTopBarIconButton(
                    systemImage: "line.3.horizontal",
                    accessibilityLabel: "Open menu",
                    action: {}
                )
            },
            trailing: {
                BlueskyTopBarIconButton(
                    systemImage: "number",
                    accessibilityLabel: "My feeds",
                    action: {}
                )
            }
        )
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
