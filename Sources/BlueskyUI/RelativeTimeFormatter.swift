import Foundation

/// Format a `Date` as a concise single-unit relative time string the way
/// Bluesky's React Native client does (#0082). Mirrors the short-form
/// branch of RN's `useTimeAgo` (`src/lib/hooks/useTimeAgo.ts`):
///
/// - `<5s`         → `"now"`
/// - `<60s`        → `"15s"`
/// - `<60m`        → `"3m"`
/// - `<24h`        → `"9h"`
/// - `<7d`         → `"2d"`
/// - `<30d`        → `"1w"`, `"3w"`
/// - `<12mo`       → `"5mo"`
/// - otherwise     → `"1y"`, `"3y"`
///
/// One unit only — no "9 hr, 49 min" multi-unit strings. Used by the feed
/// (`PostCard`), notifications (`GroupedNotificationRow`), and any other
/// surface that wants the same compact form. Lives in `BlueskyUI` so feature
/// modules don't reinvent it.
///
/// Examples:
///
/// ```
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -3))      // "now"
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -15))     // "15s"
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -180))    // "3m"
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -32_400)) // "9h"
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -172_800))// "2d"
/// RelativeTimeFormatter.string(from: Date(timeIntervalSinceNow: -700_000))// "1w"
/// ```
public enum RelativeTimeFormatter {

    private static let now: TimeInterval = 5
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 60 * 60 * 24
    private static let week: TimeInterval = 60 * 60 * 24 * 7
    private static let month: TimeInterval = 60 * 60 * 24 * 30
    private static let year: TimeInterval = 60 * 60 * 24 * 365

    /// Short-form single-unit relative-time string. `reference` defaults to
    /// `Date.now`; pass an explicit reference for deterministic tests.
    public static func string(from date: Date, reference: Date = .now) -> String {
        let elapsed = reference.timeIntervalSince(date)
        // Future timestamps (or near-zero) read as "now" — matches RN's
        // `dateDiff` returning the `now` unit when `earlier > later`.
        if elapsed < now { return "now" }
        if elapsed < minute { return "\(Int(elapsed))s" }
        if elapsed < hour { return "\(Int(elapsed / minute))m" }
        if elapsed < day { return "\(Int(elapsed / hour))h" }
        if elapsed < week { return "\(Int(elapsed / day))d" }
        if elapsed < month { return "\(Int(elapsed / week))w" }
        if elapsed < year { return "\(Int(elapsed / month))mo" }
        return "\(Int(elapsed / year))y"
    }
}
