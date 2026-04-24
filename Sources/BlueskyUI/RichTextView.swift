import SwiftUI
import BlueskyCore

/// Renders AT Protocol rich text with `RichTextFacet` spans as tappable `AttributedString` runs.
///
/// Mentions, URLs, and hashtags are coloured with `theme.colors.link` and carry a deep-link URL:
/// - mentions → `bluesky://profile/<did>`
/// - links → the original URI
/// - tags → `bluesky://hashtag/<tag>`
///
/// Callers supply an `onLinkTap` callback to handle navigation; the default is a no-op.
public struct RichTextView: View {

    let text: String
    let facets: [RichTextFacet]?
    let font: Font
    let foregroundColor: Color
    let linkColor: Color
    var onLinkTap: (URL) -> Void

    public init(
        text: String,
        facets: [RichTextFacet]? = nil,
        font: Font = Typography.body,
        foregroundColor: Color = .primary,
        linkColor: Color = Color(.sRGB, red: 0, green: 0.52, blue: 1),
        onLinkTap: @escaping (URL) -> Void = { _ in }
    ) {
        self.text = text
        self.facets = facets
        self.font = font
        self.foregroundColor = foregroundColor
        self.linkColor = linkColor
        self.onLinkTap = onLinkTap
    }

    public var body: some View {
        Text(attributed)
            .font(font)
            .environment(\.openURL, OpenURLAction { url in
                onLinkTap(url)
                return .handled
            })
    }

    // MARK: - AttributedString construction

    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = foregroundColor

        guard let facets else { return result }

        let utf8 = text.utf8
        for facet in facets {
            guard let range = byteRange(
                start: facet.index.byteStart,
                end: facet.index.byteEnd,
                utf8: utf8,
                attrString: result
            ) else { continue }

            for feature in facet.features {
                switch feature {
                case .mention(let did):
                    let url = URL(string: "bluesky://profile/\(did.rawValue)")
                    result[range].link = url
                    result[range].foregroundColor = linkColor

                case .link(let uri):
                    if let url = URL(string: uri) {
                        result[range].link = url
                    }
                    result[range].foregroundColor = linkColor

                case .tag(let tag):
                    let url = URL(string: "bluesky://hashtag/\(tag)")
                    result[range].link = url
                    result[range].foregroundColor = linkColor

                case .unknown:
                    break
                }
            }
        }
        return result
    }

    /// Converts a UTF-8 byte range into an `AttributedString` range.
    private func byteRange(
        start: Int,
        end: Int,
        utf8: String.UTF8View,
        attrString: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard start >= 0, end > start, end <= utf8.count else { return nil }

        let utf8Start = utf8.index(utf8.startIndex, offsetBy: start)
        let utf8End   = utf8.index(utf8.startIndex, offsetBy: end)

        guard let strStart = utf8Start.samePosition(in: text),
              let strEnd   = utf8End.samePosition(in: text) else { return nil }

        return Range(strStart..<strEnd, in: attrString)
    }
}

#Preview("RichTextView") {
    let text = "Hello @alice.bsky.social! Check out https://bsky.app and #bluesky"
    RichTextView(
        text: text,
        facets: [
            RichTextFacet(
                index: ByteSlice(byteStart: 6, byteEnd: 24),
                features: [.mention(did: DID(rawValue: "did:plc:alice"))]
            ),
            RichTextFacet(
                index: ByteSlice(byteStart: 37, byteEnd: 53),
                features: [.link(uri: "https://bsky.app")]
            ),
            RichTextFacet(
                index: ByteSlice(byteStart: 58, byteEnd: 66),
                features: [.tag(tag: "bluesky")]
            ),
        ]
    )
    .padding()
}
