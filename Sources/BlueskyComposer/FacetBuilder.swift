import Foundation
import BlueskyCore

/// Builds `RichTextFacet` values from plain text by scanning for @mention and #hashtag patterns.
///
/// Mentions require the caller to supply a DID mapping (built during autocomplete selection).
/// Hashtags are detected via regex and stored as `tag` facets.
public enum FacetBuilder {

    /// Scans `text` for `#hashtag` patterns and returns facets with byte-accurate ranges.
    /// Mention facets for DIDs in `mentionDIDs` are also included.
    public static func build(
        from text: String,
        mentionDIDs: [String: DID] = [:]   // keyed by the @handle string as typed
    ) -> [RichTextFacet] {
        var facets: [RichTextFacet] = []
        let utf8 = Array(text.utf8)

        // Hashtags
        let tagPattern = /#[\w]+/
        for match in text.matches(of: tagPattern) {
            guard let byteRange = byteRange(of: match.range, in: text) else { continue }
            let tag = String(text[match.range].dropFirst()) // strip leading #
            facets.append(RichTextFacet(
                index: ByteSlice(byteStart: byteRange.lowerBound, byteEnd: byteRange.upperBound),
                features: [.tag(tag: tag)]
            ))
        }

        // Mentions (only those with a resolved DID)
        let mentionPattern = /@[\w.]+/
        for match in text.matches(of: mentionPattern) {
            let handle = String(text[match.range].dropFirst()) // strip leading @
            guard let did = mentionDIDs[handle] else { continue }
            guard let byteRange = byteRange(of: match.range, in: text) else { continue }
            facets.append(RichTextFacet(
                index: ByteSlice(byteStart: byteRange.lowerBound, byteEnd: byteRange.upperBound),
                features: [.mention(did: did)]
            ))
        }

        _ = utf8 // suppress unused warning
        return facets.sorted { $0.index.byteStart < $1.index.byteStart }
    }

    // MARK: - Helpers

    private static func byteRange(
        of range: Range<String.Index>,
        in text: String
    ) -> Range<Int>? {
        let utf8 = text.utf8
        guard let lower = range.lowerBound.samePosition(in: utf8),
              let upper = range.upperBound.samePosition(in: utf8) else { return nil }
        let start = utf8.distance(from: utf8.startIndex, to: lower)
        let end   = utf8.distance(from: utf8.startIndex, to: upper)
        return start..<end
    }
}
