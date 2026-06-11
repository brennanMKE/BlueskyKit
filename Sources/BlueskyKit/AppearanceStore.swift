import Foundation
import Observation
import OSLog
import BlueskyCore

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "AppearanceStore"
)

// MARK: - AppearanceColorMode

/// User-selectable color-mode preference, distinct from the system trait collection.
///
/// Mirrors React Native's `colorMode` shell preference (`system` / `light` /
/// `dark`). When `.system`, the SwiftUI shell does not apply
/// `.preferredColorScheme(_:)` and the host trait collection wins; the other
/// two values force the SwiftUI color scheme.
public enum AppearanceColorMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

// MARK: - DarkThemeVariant

/// Dark-mode visual variant — Bluesky's full-contrast `dark` palette versus the
/// lower-contrast `dim` palette used in OLED contexts. Only meaningful when the
/// active color scheme is dark.
public enum DarkThemeVariant: String, Codable, CaseIterable, Sendable {
    /// Lower-contrast variant; matches RN's "Dim" preset and the existing
    /// `BlueskyTheme.dim` palette in `BlueskyUI`.
    case dim
    /// Full-contrast variant; matches RN's "Dark" preset and the existing
    /// `BlueskyTheme.dark` palette in `BlueskyUI`.
    case dark
}

// MARK: - AppearanceFontFamily

/// Font-family preference: system fonts versus Bluesky's branded font.
///
/// Mirrors RN's `fonts.family` of `'system' | 'theme'`. The branded font is
/// "Inter" in RN; SwiftUI keeps the picker so the preference persists, even
/// when no branded font is bundled — the rendering layer can fall back to the
/// system font without losing the user's choice.
public enum AppearanceFontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case theme
}

// MARK: - AppearanceFontSize

/// Discrete font-size tiers replacing the continuous slider. The five tiers
/// map to specific body-text point sizes; other text styles scale proportionally
/// off the body size.
public enum AppearanceFontSize: String, Codable, CaseIterable, Sendable {
    case xs
    case s
    case m
    case l
    case xl

    /// Body-text point size for this tier.
    public var bodyPointSize: Double {
        switch self {
        case .xs: return 14
        case .s:  return 15
        case .m:  return 16
        case .l:  return 17
        case .xl: return 18
        }
    }

    /// App-wide typography multiplier for this tier, applied to every
    /// `Typography` token via the `blueskyFontScale` environment value.
    ///
    /// RN parity: ALF's `computeFontScaleMultiplier` (`src/alf/fonts.ts` at
    /// baseline `46b8a58`) steps `fontScale` in `factor = 0.0625` (1/16)
    /// increments off the 16 pt body size — `'-1'` → 0.9375, `'0'` → 1,
    /// `'1'` → 1.0625. RN scaffolds `'-2'`/`'2'` tiers but clamps them to the
    /// ±1 multipliers (commented `// unused`); our shipped picker already
    /// exposes five *distinct* body sizes (14–18 pt, #0065), so XS / XL
    /// extend the same linear 1/16 step to 0.875 / 1.125 rather than
    /// collapsing onto S / L.
    ///
    /// Derived from `bodyPointSize / 16` so the Appearance preview (which
    /// renders at `bodyPointSize`) and the app-wide scale can never drift.
    public var scaleMultiplier: Double { bodyPointSize / 16 }

    /// Short user-facing label (XS / S / M / L / XL).
    public var shortLabel: String {
        switch self {
        case .xs: return "XS"
        case .s:  return "S"
        case .m:  return "M"
        case .l:  return "L"
        case .xl: return "XL"
        }
    }

    /// Default tier when no preference is stored.
    public static var `default`: AppearanceFontSize { .m }
}

// MARK: - AppearanceStore

/// Shared, app-root–level appearance preferences.
///
/// One instance is created in app `boot()` and held both by the SwiftUI shell
/// (which applies `.preferredColorScheme(_:)` and `.blueskyTheme(_:)` based on
/// the current values) and by the Settings screen (which mutates them via
/// pickers). Mutations write through to the injected `PreferencesStore`.
@MainActor
@Observable
public final class AppearanceStore {

    // MARK: - Persistence keys

    private enum PrefKey {
        static let colorMode = "appearance.colorMode"
        static let darkVariant = "appearance.darkVariant"
        static let fontFamily = "appearance.fontFamily"
        static let fontSize = "appearance.fontSize"
    }

    // MARK: - State

    public var colorMode: AppearanceColorMode {
        didSet { persist(colorMode.rawValue, key: PrefKey.colorMode) }
    }

    public var darkVariant: DarkThemeVariant {
        didSet { persist(darkVariant.rawValue, key: PrefKey.darkVariant) }
    }

    public var fontFamily: AppearanceFontFamily {
        didSet { persist(fontFamily.rawValue, key: PrefKey.fontFamily) }
    }

    public var fontSize: AppearanceFontSize {
        didSet { persist(fontSize.rawValue, key: PrefKey.fontSize) }
    }

    // MARK: - Dependencies

    private let preferences: any PreferencesStore

    // MARK: - Init

    /// Create a store and seed it from the injected `PreferencesStore`. Missing
    /// or corrupt values fall back to RN-parity defaults (System / Dim / System
    /// / M).
    public init(preferences: any PreferencesStore) {
        self.preferences = preferences

        // Seed from persistence; defaults match RN's initial values.
        self.colorMode = AppearanceStore.load(
            preferences: preferences,
            key: PrefKey.colorMode,
            default: .system,
            map: AppearanceColorMode.init(rawValue:)
        )
        self.darkVariant = AppearanceStore.load(
            preferences: preferences,
            key: PrefKey.darkVariant,
            default: .dim,
            map: DarkThemeVariant.init(rawValue:)
        )
        self.fontFamily = AppearanceStore.load(
            preferences: preferences,
            key: PrefKey.fontFamily,
            default: .system,
            map: AppearanceFontFamily.init(rawValue:)
        )
        self.fontSize = AppearanceStore.load(
            preferences: preferences,
            key: PrefKey.fontSize,
            default: .default,
            map: AppearanceFontSize.init(rawValue:)
        )
    }

    // MARK: - Helpers

    private func persist(_ rawValue: String, key: String) {
        do {
            try preferences.set(rawValue, for: key)
        } catch {
            logger.error(
                "Failed to save appearance pref \(key, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func load<T>(
        preferences: any PreferencesStore,
        key: String,
        default defaultValue: T,
        map: (String) -> T?
    ) -> T {
        do {
            if let raw = try preferences.get(String.self, for: key),
               let parsed = map(raw) {
                return parsed
            }
            return defaultValue
        } catch {
            logger.warning(
                "Failed to load appearance pref \(key, privacy: .public): \(error.localizedDescription, privacy: .public). Using default."
            )
            return defaultValue
        }
    }
}
