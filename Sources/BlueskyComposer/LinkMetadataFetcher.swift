import Foundation
import OSLog

private enum LinkMetadataLog {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
        category: "LinkMetadataFetcher"
    )
}

/// Resolved metadata for a URL, used to render link card previews in the composer.
public struct LinkMetadata: Sendable, Equatable {
    public let url: URL
    public let title: String
    public let description: String
    public let imageURL: URL?

    public nonisolated init(url: URL, title: String, description: String, imageURL: URL?) {
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
    }
}

/// Fetches OpenGraph / HTML metadata for a URL by downloading the head of the document
/// and scanning for `og:title`, `og:description`, `og:image`, falling back to
/// `<title>` / `<meta name="description">` when the OpenGraph tags are missing.
///
/// This is an actor-isolated, cancellable fetcher used by the composer to populate
/// link card previews without a server-side proxy.
public actor LinkMetadataFetcher {

    private let session: URLSession
    private var inFlight: [URL: Task<LinkMetadata?, Never>] = [:]
    private var cache: [URL: LinkMetadata] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ url: URL) async -> LinkMetadata? {
        if let cached = cache[url] { return cached }
        if let task = inFlight[url] { return await task.value }
        let task = Task<LinkMetadata?, Never> { [session] in
            await Self.performFetch(url: url, session: session)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache[url] = result }
        return result
    }

    private nonisolated static func performFetch(url: URL, session: URLSession) async -> LinkMetadata? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (compatible; Bluesky-SwiftUI link preview)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            // Limit parsing to first 256 KB to avoid blowing up on huge pages.
            let limited = data.prefix(256 * 1024)
            let encoding = Self.detectEncoding(from: http) ?? .utf8
            guard let html = String(data: limited, encoding: encoding) ?? String(data: limited, encoding: .isoLatin1) else {
                return nil
            }
            return Self.parse(html: html, baseURL: url)
        } catch {
            LinkMetadataLog.logger.error("metadata fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func detectEncoding(from response: HTTPURLResponse) -> String.Encoding? {
        guard let charset = response.value(forHTTPHeaderField: "Content-Type")?
            .lowercased()
            .split(separator: ";")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("charset=") })?
            .replacingOccurrences(of: "charset=", with: "")
        else { return nil }
        switch charset {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1252": return .windowsCP1252
        default: return nil
        }
    }

    // MARK: - Parsing

    nonisolated static func parse(html: String, baseURL: URL) -> LinkMetadata {
        let head = Self.extractHead(from: html)
        let ogTitle = Self.metaContent(in: head, attribute: "property", value: "og:title")
            ?? Self.metaContent(in: head, attribute: "name", value: "twitter:title")
        let ogDescription = Self.metaContent(in: head, attribute: "property", value: "og:description")
            ?? Self.metaContent(in: head, attribute: "name", value: "twitter:description")
            ?? Self.metaContent(in: head, attribute: "name", value: "description")
        let ogImage = Self.metaContent(in: head, attribute: "property", value: "og:image")
            ?? Self.metaContent(in: head, attribute: "name", value: "twitter:image")
        let titleTag = Self.extractTitleTag(in: head)

        let title = ogTitle ?? titleTag ?? (baseURL.host ?? baseURL.absoluteString)
        let description = ogDescription ?? ""
        let imageURL = ogImage.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        return LinkMetadata(
            url: baseURL,
            title: Self.decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
            description: Self.decodeEntities(description).trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: imageURL
        )
    }

    private nonisolated static func extractHead(from html: String) -> String {
        // Case-insensitive search for </head>; if missing, scan the full document.
        let lower = html.lowercased()
        if let endRange = lower.range(of: "</head>") {
            return String(html[..<endRange.lowerBound])
        }
        return html
    }

    private nonisolated static func extractTitleTag(in html: String) -> String? {
        let pattern = "<title[^>]*>([\\s\\S]*?)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: html) else { return nil }
        let raw = String(html[r])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func metaContent(in html: String, attribute: String, value: String) -> String? {
        // Match <meta ... attribute="value" ... content="..."> with either order of attribute/content.
        let escaped = NSRegularExpression.escapedPattern(for: value)
        let attr = NSRegularExpression.escapedPattern(for: attribute)
        let patterns = [
            // attribute first, then content
            "<meta[^>]*\\b\(attr)\\s*=\\s*[\"']\(escaped)[\"'][^>]*\\bcontent\\s*=\\s*[\"']([^\"']*)[\"'][^>]*/?>",
            // content first, then attribute
            "<meta[^>]*\\bcontent\\s*=\\s*[\"']([^\"']*)[\"'][^>]*\\b\(attr)\\s*=\\s*[\"']\(escaped)[\"'][^>]*/?>"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: html) {
                let value = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private nonisolated static func decodeEntities(_ s: String) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        for (k, v) in pairs { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities (decimal) — &#NNN;
        if let regex = try? NSRegularExpression(pattern: "&#([0-9]+);", options: []) {
            let range = NSRange(out.startIndex..., in: out)
            let matches = regex.matches(in: out, options: [], range: range).reversed()
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let numRange = Range(match.range(at: 1), in: out),
                      let full = Range(match.range, in: out),
                      let code = UInt32(out[numRange]),
                      let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return out
    }
}
