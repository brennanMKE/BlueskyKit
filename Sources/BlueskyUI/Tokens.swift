import SwiftUI

// MARK: - Spacing

/// Spacing token scale.  Matches the ALF xxs → 2xl t-shirt-size naming.
/// Values follow a 4 pt base grid (xxs=2, xs=4, sm=8, md=12, lg=16, xl=24, 2xl=32).
public enum Spacing {
    public static let _2xs: CGFloat = 2
    public static let xs:   CGFloat = 4
    public static let sm:   CGFloat = 8
    public static let md:   CGFloat = 12
    public static let lg:   CGFloat = 16
    public static let xl:   CGFloat = 24
    public static let _2xl: CGFloat = 32
}

// MARK: - Typography

/// Typography token scale.  Font sizes match Bluesky's ALF text-size atoms.
public enum Typography {
    // MARK: Font sizes
    public static let xs:  CGFloat = 12
    public static let sm:  CGFloat = 14
    public static let md:  CGFloat = 16
    public static let lg:  CGFloat = 18
    public static let xl:  CGFloat = 20
    public static let _2xl: CGFloat = 28

    // MARK: Line height multipliers
    public static let leadingTight:  CGFloat = 1.1
    public static let leadingSnug:   CGFloat = 1.25
    public static let leadingNormal: CGFloat = 1.5

    // MARK: Font factories

    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static var bodySmall: Font  { font(sm) }
    public static var body: Font       { font(md) }
    public static var bodyLarge: Font  { font(lg) }
    public static var headline: Font   { font(md, weight: .semibold) }
    public static var title: Font      { font(xl, weight: .semibold) }
    public static var largeTitle: Font { font(_2xl, weight: .bold) }
    public static var footnote: Font   { font(xs) }

    // MARK: Scaled font factories (#0200)

    // Variants that honor the user's Font Size tier. Pass the
    // `blueskyFontScale` environment value; mirrors RN ALF's
    // `normalizeTextStyles`, which multiplies every text atom's `fontSize`
    // by the device `fontScale` multiplier (`src/alf/typography.tsx`).

    public static func bodySmall(scale: CGFloat) -> Font  { font(sm * scale) }
    public static func body(scale: CGFloat) -> Font       { font(md * scale) }
    public static func bodyLarge(scale: CGFloat) -> Font  { font(lg * scale) }
    public static func headline(scale: CGFloat) -> Font   { font(md * scale, weight: .semibold) }
    public static func footnote(scale: CGFloat) -> Font   { font(xs * scale) }
}

// MARK: - Font scale environment (#0200)

extension EnvironmentValues {
    /// App-wide typography multiplier driven by the user's Font Size tier
    /// (Settings → Appearance). The app shell injects
    /// `AppearanceFontSize.scaleMultiplier` here; content views multiply it
    /// into the `Typography` sizes for the main reading surfaces (post body,
    /// author header, embeds). RN parity: ALF's `fontScale` device preference
    /// applied through `normalizeTextStyles`.
    @Entry public var blueskyFontScale: CGFloat = 1
}

public extension View {
    /// Injects the app-wide typography multiplier into the SwiftUI
    /// environment. Applied once at the shell root (next to
    /// `.blueskyTheme(_:)`) — content screens read it via
    /// `@Environment(\.blueskyFontScale)` and must not re-inject it.
    func blueskyFontScale(_ scale: CGFloat) -> some View {
        environment(\.blueskyFontScale, scale)
    }
}
