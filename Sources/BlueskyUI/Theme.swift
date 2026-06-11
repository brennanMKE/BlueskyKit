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

    // Hex values transcribed from the Bluesky ALF design system (`@bsky.app/alf` 0.1.7,
    // the version pinned by the RN client at the migration baseline commit 46b8a58).
    //
    // Token mapping (Swift role → ALF palette slot, per `createTheme` in alf/themes.ts):
    //   background          → contrast_0     (atoms.bg)
    //   backgroundSecondary → contrast_25    (atoms.bg_contrast_25)
    //   textPrimary         → contrast_1000  (atoms.text)
    //   textSecondary       → contrast_700   (atoms.text_contrast_medium)
    //   textTertiary        → contrast_400   (atoms.text_contrast_low)
    //   link                → primary_500
    //   like                → pink (static across themes)
    //   border              → contrast_100   (atoms.border_contrast_low)
    //   borderSubtle        → contrast_50
    //   error               → negative_500
    //   success             → positive_500
    //
    // `.light` reads DEFAULT_PALETTE directly, `.dark` is invertPalette(DEFAULT_PALETTE),
    // `.dim` is invertPalette(DEFAULT_SUBDUED_PALETTE) — exactly as ALF's createThemes does.

    public static let light = BlueskyTheme(
        variant: .light,
        colors: Colors(
            background:          Color(srgb: 0xFF_FF_FF),
            backgroundSecondary: Color(srgb: 0xF9_FA_FB),
            textPrimary:         Color(srgb: 0x00_00_00),
            textSecondary:       Color(srgb: 0x40_51_68),
            textTertiary:        Color(srgb: 0x87_98_B0),
            link:                Color(srgb: 0x00_6A_FF),
            like:                Color(srgb: 0xEC_48_99),
            border:              Color(srgb: 0xDC_E2_EA),
            borderSubtle:        Color(srgb: 0xEF_F2_F6),
            error:               Color(srgb: 0xE9_16_46),
            success:             Color(srgb: 0x09_B3_5E)
        )
    )

    public static let dark = BlueskyTheme(
        variant: .dark,
        colors: Colors(
            background:          Color(srgb: 0x00_00_00),
            backgroundSecondary: Color(srgb: 0x11_18_22),
            textPrimary:         Color(srgb: 0xFF_FF_FF),
            textSecondary:       Color(srgb: 0xA5_B2_C5),
            textTertiary:        Color(srgb: 0x52_65_80),
            link:                Color(srgb: 0x00_6A_FF),
            like:                Color(srgb: 0xEC_48_99),
            border:              Color(srgb: 0x23_2E_3E),
            borderSubtle:        Color(srgb: 0x19_22_2E),
            error:               Color(srgb: 0xE9_16_46),
            success:             Color(srgb: 0x09_B3_5E)
        )
    )

    public static let dim = BlueskyTheme(
        variant: .dim,
        colors: Colors(
            background:          Color(srgb: 0x15_1D_28),
            backgroundSecondary: Color(srgb: 0x1C_27_36),
            textPrimary:         Color(srgb: 0xFF_FF_FF),
            textSecondary:       Color(srgb: 0xAB_B8_C9),
            textTertiary:        Color(srgb: 0x58_6C_89),
            link:                Color(srgb: 0x0F_73_FF),
            like:                Color(srgb: 0xEC_48_99),
            border:              Color(srgb: 0x2C_3A_4E),
            borderSubtle:        Color(srgb: 0x22_2E_3F),
            error:               Color(srgb: 0xEB_24_52),
            success:             Color(srgb: 0x0A_C2_66)
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
    ///
    /// The app shell (`AppearanceShellModifier` in the app target) injects the
    /// user's resolved theme — including the dark-variant choice between
    /// `.dark` and `.dim` — at the root, so content screens must *not*
    /// re-inject a theme themselves; doing so discards the variant preference
    /// (#0199). Use this modifier only at the root of a hierarchy that has no
    /// themed ancestor (the shell itself, previews, and component galleries).
    func blueskyTheme(_ theme: BlueskyTheme) -> some View {
        environment(\.blueskyTheme, theme)
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
