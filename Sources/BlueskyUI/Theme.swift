import SwiftUI

// MARK: - BlueskyTheme

/// The application's visual theme: light, dark, or dim.
///
/// Inject via SwiftUI's environment using the `.blueskyTheme` key, then read with
/// `@Environment(\.blueskyTheme)`. All color values are drawn from the Bluesky ALF
/// design system palette.
public struct BlueskyTheme: Sendable, Equatable {

    public enum Variant: String, Sendable, Equatable, CaseIterable {
        case light, dark, dim
    }

    public let variant: Variant
    public let colors: Colors

    public struct Colors: Sendable, Equatable {
        // Surfaces
        public let background: Color
        public let backgroundSecondary: Color
        // Text
        public let textPrimary: Color
        public let textSecondary: Color
        public let textTertiary: Color
        // Interactive
        public let link: Color
        public let like: Color
        // Borders
        public let border: Color
        public let borderSubtle: Color
        // Status
        public let error: Color
        public let success: Color
    }
}

// MARK: - Built-in themes

extension BlueskyTheme {

    // Hex values sourced from the Bluesky ALF gray/blue scales used in the React Native app.

    public static let light = BlueskyTheme(
        variant: .light,
        colors: Colors(
            background:          Color(srgb: 0xFF_FF_FF),
            backgroundSecondary: Color(srgb: 0xF1_F3_F5),
            textPrimary:         Color(srgb: 0x0F_14_19),
            textSecondary:       Color(srgb: 0x53_64_71),
            textTertiary:        Color(srgb: 0x8B_98_A5),
            link:                Color(srgb: 0x00_85_FF),
            like:                Color(srgb: 0xEC_48_99),
            border:              Color(srgb: 0xE7_EC_F0),
            borderSubtle:        Color(srgb: 0xF1_F3_F5),
            error:               Color(srgb: 0xE5_39_35),
            success:             Color(srgb: 0x20_BC_07)
        )
    )

    public static let dark = BlueskyTheme(
        variant: .dark,
        colors: Colors(
            background:          Color(srgb: 0x16_1E_27),
            backgroundSecondary: Color(srgb: 0x1E_2D_3D),
            textPrimary:         Color(srgb: 0xF1_F3_F5),
            textSecondary:       Color(srgb: 0x8B_98_A5),
            textTertiary:        Color(srgb: 0x59_70_8A),
            link:                Color(srgb: 0x20_8B_FE),
            like:                Color(srgb: 0xEC_48_99),
            border:              Color(srgb: 0x2A_3A_4A),
            borderSubtle:        Color(srgb: 0x1E_2D_3D),
            error:               Color(srgb: 0xEF_53_50),
            success:             Color(srgb: 0x20_BC_07)
        )
    )

    public static let dim = BlueskyTheme(
        variant: .dim,
        colors: Colors(
            background:          Color(srgb: 0x15_20_2B),
            backgroundSecondary: Color(srgb: 0x1E_2D_3D),
            textPrimary:         Color(srgb: 0xF7_F9_F9),
            textSecondary:       Color(srgb: 0x8B_98_A5),
            textTertiary:        Color(srgb: 0x59_70_8A),
            link:                Color(srgb: 0x1D_9B_F0),
            like:                Color(srgb: 0xF9_18_80),
            border:              Color(srgb: 0x2F_33_36),
            borderSubtle:        Color(srgb: 0x1E_2D_3D),
            error:               Color(srgb: 0xFF_60_60),
            success:             Color(srgb: 0x00_BA_7C)
        )
    )
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry public var blueskyTheme: BlueskyTheme = .light
}

// MARK: - View modifier

public extension View {
    /// Injects a `BlueskyTheme` into the SwiftUI environment.
    func blueskyTheme(_ theme: BlueskyTheme) -> some View {
        environment(\.blueskyTheme, theme)
    }

    /// Injects a `BlueskyTheme` that automatically tracks the system appearance.
    /// Uses `.dark` when the OS is in dark mode and `.light` otherwise.
    func adaptiveBlueskyTheme() -> some View {
        modifier(AdaptiveBlueskyThemeModifier())
    }
}

// MARK: - Adaptive modifier

private struct AdaptiveBlueskyThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.blueskyTheme, colorScheme == .dark ? .dark : .light)
    }
}

// MARK: - Color helper

private extension Color {
    /// Initialize from a packed 24-bit sRGB integer (e.g. `0xFF_85_00`).
    init(srgb hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b)
    }
}
