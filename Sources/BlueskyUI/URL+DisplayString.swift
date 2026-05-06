import Foundation

/// Render a URL the way Bluesky surfaces external links in user-facing chrome:
/// the protocol prefix and any trailing slash are dropped while the underlying
/// URL stays intact for navigation.
///
/// Used by the profile info row (#0084) when surfacing the user-supplied
/// website link, and reusable anywhere else a URL needs the same treatment.
///
/// Examples:
///
/// ```
/// URL(string: "https://brennan.sstools.co")?.displayString // "brennan.sstools.co"
/// URL(string: "http://example.com/")?.displayString        // "example.com"
/// URL(string: "https://example.com/path/")?.displayString  // "example.com/path"
/// ```
extension URL {

    /// The URL formatted for display: drops the `http://` / `https://` scheme
    /// prefix and any single trailing slash. The original URL value is left
    /// untouched so callers can keep using `self` for navigation.
    public var displayString: String {
        var s = absoluteString
        if s.hasPrefix("https://") {
            s.removeFirst("https://".count)
        } else if s.hasPrefix("http://") {
            s.removeFirst("http://".count)
        }
        if s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }
}

extension String {

    /// Convenience equivalent to `URL.displayString` that operates on a raw
    /// string — useful when the source is a free-text URL (e.g. inside a
    /// profile description) that has not yet been parsed into a `URL`.
    public var urlDisplayString: String {
        var s = self
        if s.hasPrefix("https://") {
            s.removeFirst("https://".count)
        } else if s.hasPrefix("http://") {
            s.removeFirst("http://".count)
        }
        if s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }
}
