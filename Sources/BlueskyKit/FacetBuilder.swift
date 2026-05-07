import Foundation
import OSLog
import BlueskyCore

private let facetBuilderLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "FacetBuilder"
)

/// Builds `RichTextFacet` values from plain text by scanning for `@mention`,
/// `#hashtag`, and URL patterns and emitting UTF-8 byte-accurate ranges.
///
/// The synchronous `build(from:mentionDIDs:)` flavour is used by the post
/// composer — it relies on the autocomplete UI to pre-resolve each typed handle
/// to a DID and pass the mapping in. Hashtags and URLs are detected without
/// any network access.
///
/// The asynchronous `buildAsync(from:network:)` flavour is used by the DM
/// compose bar where there is no autocomplete: every detected `@handle` is
/// resolved through `com.atproto.identity.resolveHandle` on the fly. Handles
/// that fail to resolve are silently dropped from the facet list (matching
/// RN's `stripInvalidMentions` behaviour) so the recipient never sees a
/// dangling mention pill.
///
/// Lives in `BlueskyKit` (Layer 1) so both `BlueskyComposer` (post) and
/// `BlueskyMessages` (DM) can share a single byte-accurate implementation —
/// Layer-3 modules cannot depend on each other directly.
public enum FacetBuilder {

    // MARK: - Synchronous build (post composer path)

    /// Scans `text` for `#hashtag`, `@mention`, and URL patterns and returns
    /// facets with byte-accurate ranges. Mention facets are emitted only for
    /// handles whose DID is present in `mentionDIDs` — handles without an
    /// entry are skipped. URLs and hashtags are detected without any
    /// out-of-band lookup.
    public static func build(
        from text: String,
        mentionDIDs: [String: DID] = [:]   // keyed by the @handle string as typed
    ) -> [RichTextFacet] {
        var facets: [RichTextFacet] = []

        // Hashtags
        for (range, tag) in detectHashtags(in: text) {
            guard let byteRange = byteRange(of: range, in: text) else { continue }
            facets.append(RichTextFacet(
                index: ByteSlice(byteStart: byteRange.lowerBound, byteEnd: byteRange.upperBound),
                features: [.tag(tag: tag)]
            ))
        }

        // Mentions (only those with a resolved DID)
        for (range, handle) in detectMentions(in: text) {
            guard let did = mentionDIDs[handle] else { continue }
            guard let byteRange = byteRange(of: range, in: text) else { continue }
            facets.append(RichTextFacet(
                index: ByteSlice(byteStart: byteRange.lowerBound, byteEnd: byteRange.upperBound),
                features: [.mention(did: did)]
            ))
        }

        // Links (http / https URLs)
        for (range, uri) in detectLinks(in: text) {
            guard let byteRange = byteRange(of: range, in: text) else { continue }
            facets.append(RichTextFacet(
                index: ByteSlice(byteStart: byteRange.lowerBound, byteEnd: byteRange.upperBound),
                features: [.link(uri: uri)]
            ))
        }

        return facets.sorted { $0.index.byteStart < $1.index.byteStart }
    }

    // MARK: - Asynchronous build (DM compose bar path)

    /// Asynchronous variant that resolves every `@handle` to a DID via
    /// `com.atproto.identity.resolveHandle`. Hashtags and URLs are detected
    /// the same way as the synchronous flavour — only mentions need the
    /// network. Handles that fail to resolve (or look obviously malformed)
    /// are skipped, matching RN's `detectFacets` + `stripInvalidMentions`
    /// pipeline used by `MessagesList.tsx#onSendMessage`.
    public static func buildAsync(
        from text: String,
        network: any NetworkClient
    ) async -> [RichTextFacet] {
        // Resolve every detected handle in parallel — most messages have at
        // most one or two mentions, so a TaskGroup with a small fanout is
        // simpler than batching.
        let mentionRanges = detectMentions(in: text)
        var resolved: [String: DID] = [:]
        if !mentionRanges.isEmpty {
            resolved = await withTaskGroup(of: (String, DID?).self) { group in
                let uniqueHandles = Set(mentionRanges.map(\.handle))
                for handle in uniqueHandles {
                    group.addTask {
                        let did = await Self.resolveHandle(handle, network: network)
                        return (handle, did)
                    }
                }
                var map: [String: DID] = [:]
                for await (handle, did) in group {
                    if let did { map[handle] = did }
                }
                return map
            }
        }
        return build(from: text, mentionDIDs: resolved)
    }

    /// Whether the message contains any detectable facet — used by the
    /// compose bar to decide whether to bother building facets at all and to
    /// drive a future inline-highlighting pass. Pure string scanning, no
    /// network.
    public static func hasDetectableFacets(in text: String) -> Bool {
        !detectHashtags(in: text).isEmpty
            || !detectMentions(in: text).isEmpty
            || !detectLinks(in: text).isEmpty
    }

    // MARK: - Detection helpers

    /// Detect `#tag` ranges in `text`. Returns `(range, tag-without-hash)`.
    private static func detectHashtags(in text: String) -> [(range: Range<String.Index>, tag: String)] {
        let pattern = /#[\w]+/
        return text.matches(of: pattern).map { match in
            (range: match.range, tag: String(text[match.range].dropFirst()))
        }
    }

    /// Detect `@handle` ranges in `text`. Returns `(range, handle-without-at)`.
    /// RN's regex (`detectLinkables`) accepts `@a-z0-9.-`; we mirror that and
    /// also strip a trailing `.` since RN's mention validator rejects handles
    /// with a trailing dot.
    private static func detectMentions(in text: String) -> [(range: Range<String.Index>, handle: String)] {
        let pattern = /@[a-zA-Z0-9.\-]+/
        return text.matches(of: pattern).compactMap { match in
            var handle = String(text[match.range].dropFirst())
            // Strip a trailing dot — `@alice.` should resolve `alice`, not `alice.`.
            while handle.hasSuffix(".") { handle.removeLast() }
            // Refuse `@` alone or any handle that no longer contains a dot —
            // bare `@alice` without a domain isn't a valid AT Proto handle and
            // resolveHandle would fail with InvalidHandle anyway.
            guard handle.contains(".") else { return nil }
            // Recompute the trimmed range so the byte-slice lines up with the
            // text the recipient sees (we want the pill to cover `@alice.bsky.social`,
            // not the trailing dot the user happened to type next to it).
            guard let trimmedEnd = text.index(match.range.lowerBound,
                                              offsetBy: handle.count + 1, // 1 for the @
                                              limitedBy: match.range.upperBound) else {
                return nil
            }
            return (range: match.range.lowerBound..<trimmedEnd, handle: handle)
        }
    }

    /// Detect `http(s)://…` URL ranges in `text`. Uses `NSDataDetector` for
    /// parity with the rest of the app — same behaviour as the post
    /// composer's URL detection, including handling of trailing punctuation
    /// (the detector returns the URL without it).
    private static func detectLinks(in text: String) -> [(range: Range<String.Index>, uri: String)] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            facetBuilderLogger.fault("NSDataDetector init failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )
        var results: [(range: Range<String.Index>, uri: String)] = []
        for match in matches {
            guard match.resultType == .link, let url = match.url else { continue }
            // Only record real schemes — `mailto:`, `tel:`, etc. don't belong in
            // an AT Proto link facet (RN's detection is restricted to http/https).
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                continue
            }
            guard let range = Range(match.range, in: text) else { continue }
            results.append((range: range, uri: url.absoluteString))
        }
        return results
    }

    // MARK: - Network

    /// Resolve a single `@handle` to a DID via
    /// `com.atproto.identity.resolveHandle`. Returns `nil` on any failure
    /// (network error, invalid handle, etc.) — the caller then drops the
    /// mention rather than emitting a broken facet.
    private static func resolveHandle(_ handle: String, network: any NetworkClient) async -> DID? {
        do {
            let resp: ResolveHandleResponse = try await network.get(
                lexicon: "com.atproto.identity.resolveHandle",
                params: ["handle": handle]
            )
            return resp.did
        } catch {
            facetBuilderLogger.debug(
                "resolveHandle failed for @\(handle, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Byte-range helper

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

// MARK: - Lexicon types

/// Response shape for `com.atproto.identity.resolveHandle`. Kept private to
/// `FacetBuilder` because no other module needs to make this XRPC call
/// today — the auth signup flow uses a raw URLSession path that predates
/// this helper. `nonisolated` so the `Decodable` conformance satisfies
/// `NetworkClient.get`'s `Decodable & Sendable` requirement from a
/// non-isolated call site (BlueskyKit's defaultIsolation is `MainActor`).
nonisolated private struct ResolveHandleResponse: Decodable, Sendable {
    let did: DID
}
