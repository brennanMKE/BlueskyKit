import Foundation

/// Format integer counts the way Bluesky does in user-facing chrome:
///
/// - below 1,000 → full precision with no separator (`"42"`, `"999"`)
/// - 1,000 – 999,999 → `"1.4K"` style (one decimal, trailing zero trimmed)
/// - 1,000,000 and above → `"1.4M"` / `"2M"` style
///
/// Used for post action-bar like/repost counts (#0076) and profile stats
/// (#0084). Keeping it in `BlueskyUI` so feature modules don't reinvent it.
///
/// Examples:
///
/// ```
/// CompactNumberFormatter.string(from: 0)       // "0"
/// CompactNumberFormatter.string(from: 999)     // "999"
/// CompactNumberFormatter.string(from: 1_000)   // "1K"
/// CompactNumberFormatter.string(from: 1_400)   // "1.4K"
/// CompactNumberFormatter.string(from: 12_345)  // "12.3K"
/// CompactNumberFormatter.string(from: 999_999) // "999.9K"
/// CompactNumberFormatter.string(from: 1_400_000)// "1.4M"
/// ```
public enum CompactNumberFormatter {

    /// Format `value` using Bluesky's compact-count convention.
    public static func string(from value: Int) -> String {
        if value < 0 { return "-\(string(from: -value))" }
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 { return scaled(value, divisor: 1_000, suffix: "K") }
        return scaled(value, divisor: 1_000_000, suffix: "M")
    }

    /// Internal: produce "1.4K"-style output. Drops the decimal when it would
    /// be a trailing zero ("1K" not "1.0K"). One decimal place max.
    private static func scaled(_ value: Int, divisor: Int, suffix: String) -> String {
        let scaled = Double(value) / Double(divisor)
        // Truncate (not round) to one decimal — matches RN's `Math.floor`-ish
        // display so a count of 1,499 reads as "1.4K", not "1.5K".
        let truncated = (scaled * 10).rounded(.down) / 10
        // Drop the decimal if it's an exact integer.
        if truncated == truncated.rounded(.down) {
            return "\(Int(truncated))\(suffix)"
        }
        return String(format: "%.1f%@", truncated, suffix)
    }
}
