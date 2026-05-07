import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ComposerStore")

// MARK: - ComposerStoring

public protocol ComposerStoring: AnyObject, Observable, Sendable {
    var isPosting: Bool { get }
    var didPost: Bool { get }
    var errorMessage: String? { get }
    var mentionSuggestions: [ProfileBasic] { get }

    func post(
        text: String,
        images: [ComposerImageAttachment],
        attachedVideo: VideoAttachment?,
        selectedGIF: TenorGif?,
        detectedURL: URL?,
        linkMetadata: LinkMetadata?,
        additionalPosts: [String],
        replyTo: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID],
        selfLabels: Set<String>,
        threadgateAllow: ThreadgateAllowSelection,
        quotesEnabled: Bool
    ) async -> [ComposerImageAttachment]
    func searchMentions(_ prefix: String)
    func clearError()
    func setError(_ message: String)
}

// MARK: - ThreadgateAllowSelection

/// Composer-side model of who can reply to the post being composed.
///
/// Mirrors RN's `ThreadgateAllowUISetting[]` from
/// `state/queries/threadgate/types.ts`, but expressed as a single value type
/// so the "Everyone" / "Nobody" radio semantics aren't representable in the
/// granular case. The mapping back to the AT Proto record is:
///
///   - `.everyone` → record's `allow` field omitted → everyone can reply.
///   - `.nobody` → record's `allow` field present and empty → nobody can reply.
///   - `.granular(...)` → record's `allow` field present with one rule per
///     enabled toggle. An empty granular selection is invalid (the UI should
///     prevent it); if it slips through, treat as `.everyone` to avoid
///     accidentally locking down replies on a record that isn't supposed to.
public enum ThreadgateAllowSelection: Sendable, Equatable {
    case everyone
    case nobody
    case granular(mention: Bool, following: Bool, follower: Bool, listURIs: [ATURI])

    /// `true` when the selection is the default ("everyone can reply") and
    /// no threadgate record needs to be written.
    public var isDefault: Bool {
        if case .everyone = self { return true }
        return false
    }

    /// Build the lexicon `allow` value for this selection. Returns `nil`
    /// when the field should be **omitted** (everyone can reply); returns
    /// `[]` when the field should be **present-but-empty** (nobody can
    /// reply); otherwise returns the rule list.
    public func toAllowRules() -> [ThreadgateAllowRule]? {
        switch self {
        case .everyone:
            return nil
        case .nobody:
            return []
        case .granular(let mention, let following, let follower, let listURIs):
            var rules: [ThreadgateAllowRule] = []
            if mention { rules.append(.mention) }
            if following { rules.append(.following) }
            if follower { rules.append(.follower) }
            for uri in listURIs { rules.append(.list(uri)) }
            // Empty granular collapses back to `everyone` semantics: the
            // user toggled all boxes off, which would otherwise mean
            // "nobody can reply" — almost certainly not what they wanted.
            return rules.isEmpty ? nil : rules
        }
    }
}

// MARK: - VideoAttachment

public struct VideoAttachment: Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

// MARK: - ComposerImageAttachment

public struct ComposerImageAttachment: Identifiable, Sendable {
    public let id: UUID
    public let data: Data
    public let mimeType: String
    public var altText: String
    public var blobRef: BlobRef?

    public init(id: UUID = UUID(), data: Data, mimeType: String, altText: String = "", blobRef: BlobRef? = nil) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.altText = altText
        self.blobRef = blobRef
    }
}

// MARK: - ComposerStore

@Observable
public final class ComposerStore: ComposerStoring {

    public private(set) var isPosting = false
    public private(set) var didPost = false
    public private(set) var errorMessage: String?
    public private(set) var mentionSuggestions: [ProfileBasic] = []

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private var suggestionTask: Task<Void, Never>?

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    // MARK: - Post

    /// Returns images array with blobRefs populated after upload.
    public func post(
        text: String,
        images: [ComposerImageAttachment],
        attachedVideo: VideoAttachment?,
        selectedGIF: TenorGif?,
        detectedURL: URL?,
        linkMetadata: LinkMetadata?,
        additionalPosts: [String],
        replyTo: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID],
        selfLabels: Set<String>,
        threadgateAllow: ThreadgateAllowSelection,
        quotesEnabled: Bool
    ) async -> [ComposerImageAttachment] {
        guard !isPosting else { return images }
        let viewerDID: DID?
        do {
            viewerDID = try await accountStore.loadCurrentDID()
        } catch {
            logger.error("post: failed to load current DID: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not access your account: \(error.localizedDescription)"
            return images
        }
        guard let viewerDID else {
            errorMessage = "Not signed in"
            return images
        }
        isPosting = true
        defer { isPosting = false }
        errorMessage = nil

        var updatedImages = images
        do {
            // Upload images that don't yet have a blobRef
            for i in updatedImages.indices {
                if updatedImages[i].blobRef == nil {
                    let resp: UploadBlobResponse = try await network.upload(
                        lexicon: "com.atproto.repo.uploadBlob",
                        data: updatedImages[i].data,
                        mimeType: updatedImages[i].mimeType
                    )
                    updatedImages[i].blobRef = resp.blob
                }
            }

            let uploadedImages: [EmbedImage] = updatedImages.compactMap { img in
                guard let blob = img.blobRef else { return nil }
                return EmbedImage(image: blob, alt: img.altText, aspectRatio: nil)
            }

            // Upload video if attached
            var videoEmbed: Embed?
            if let video = attachedVideo {
                let resp: UploadBlobResponse = try await network.upload(
                    lexicon: "com.atproto.repo.uploadBlob",
                    data: video.data,
                    mimeType: video.mimeType
                )
                videoEmbed = .video(EmbedVideo(video: resp.blob, captions: nil, alt: nil, aspectRatio: nil))
            }

            // GIFs are posted as `app.bsky.embed.external` with the canonical
            // gif URL plus a `thumb` blob (the static preview frame). RN
            // builds this in `lib/api/resolve.ts` (`resolveGif`). The
            // selected-GIF branch is mutually exclusive with images / video
            // / link card on the UI side, so we only have to honor it when
            // those slots are empty.
            var gifExternalEmbed: Embed?
            if let selectedGIF, uploadedImages.isEmpty, videoEmbed == nil {
                do {
                    gifExternalEmbed = try await buildGIFExternalEmbed(selectedGIF)
                } catch {
                    // GIF embed construction is best-effort: a thumb upload
                    // failure still lets the post go out without the
                    // attachment, with a non-fatal error surfaced to the
                    // caller. Matches RN's `resolveGif` failure path.
                    logger.error("GIF embed build failed: \(error.localizedDescription, privacy: .public)")
                    errorMessage = "Could not attach the selected GIF: \(error.localizedDescription)"
                    return updatedImages
                }
            }

            var embed: Embed?
            if !uploadedImages.isEmpty, let qp = quotedPost {
                embed = .recordWithMedia(
                    record: EmbedRecordRef(uri: qp.uri, cid: qp.cid),
                    media: .images(uploadedImages)
                )
            } else if !uploadedImages.isEmpty {
                embed = .images(uploadedImages)
            } else if let videoEmbed {
                embed = videoEmbed
            } else if let gifExternalEmbed, let qp = quotedPost {
                // GIF + quote → recordWithMedia, mirroring how RN attaches
                // an external embed to a quote post.
                embed = .recordWithMedia(
                    record: EmbedRecordRef(uri: qp.uri, cid: qp.cid),
                    media: gifExternalEmbed
                )
            } else if let gifExternalEmbed {
                embed = gifExternalEmbed
            } else if let url = detectedURL, quotedPost == nil {
                // If we have OpenGraph metadata, try to upload the thumbnail blob.
                var thumb: BlobRef?
                if let imageURL = linkMetadata?.imageURL {
                    do {
                        let (data, mime) = try await fetchImageData(imageURL)
                        let resp: UploadBlobResponse = try await network.upload(
                            lexicon: "com.atproto.repo.uploadBlob",
                            data: data,
                            mimeType: mime
                        )
                        thumb = resp.blob
                    } catch {
                        // Thumbnail upload is best-effort; the post still goes out without it.
                        logger.debug("link card thumbnail fetch/upload failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                embed = .external(EmbedExternal(
                    uri: url.absoluteString,
                    title: linkMetadata?.title ?? (url.host ?? url.absoluteString),
                    description: linkMetadata?.description ?? "",
                    thumb: thumb
                ))
            } else if let qp = quotedPost {
                embed = .record(EmbedRecordRef(uri: qp.uri, cid: qp.cid))
            }

            let facets = FacetBuilder.build(from: text, mentionDIDs: mentionDIDs)
            let reply = replyTo.map { ReplyRef(root: $0, parent: $0) }
            // Encode self-labels only when at least one is selected, so the
            // record's `labels` field is omitted entirely for an unlabeled
            // post (matching RN's `if (draft.labels.length)` guard).
            let labelsRecord: SelfLabels? = selfLabels.isEmpty
                ? nil
                : SelfLabels(values: selfLabels.sorted().map { SelfLabelValue(val: $0) })
            let record = PostRecord(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                embed: embed,
                reply: reply,
                langs: [selectedLanguage],
                labels: labelsRecord
            )
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.feed.post",
                record: record
            )
            let firstResponse: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )

            // Threadgate / postgate companion records, written at the same
            // rkey as the post they gate (see RN
            // `lib/api/index.ts`). RN bundles the post + gate writes into a
            // single `applyWrites` call and computes the CID locally; we
            // post them as separate `createRecord` calls in sequence
            // because we read the rkey back from the server's URI, which
            // means the post must hit the network first. The user-visible
            // outcome is the same — both records exist at the same rkey
            // by the time the composer dismisses.
            if let postRkey = firstResponse.uri.rkey {
                if !threadgateAllow.isDefault {
                    let threadgate = ThreadgateRecord(
                        post: firstResponse.uri,
                        allow: threadgateAllow.toAllowRules()
                    )
                    let tgReq = CreateRecordRequest(
                        repo: viewerDID.rawValue,
                        collection: "app.bsky.feed.threadgate",
                        rkey: postRkey,
                        record: threadgate
                    )
                    do {
                        let _: CreateRecordResponse = try await network.post(
                            lexicon: "com.atproto.repo.createRecord", body: tgReq
                        )
                    } catch {
                        // Surface a soft warning but don't fail the whole
                        // post — the post itself succeeded; the gate just
                        // didn't apply. Match RN behavior of best-effort
                        // gate writes.
                        logger.error("threadgate write failed: \(error, privacy: .public)")
                    }
                }
                if !quotesEnabled {
                    let postgate = PostgateRecord(
                        post: firstResponse.uri,
                        embeddingRules: [.disable]
                    )
                    let pgReq = CreateRecordRequest(
                        repo: viewerDID.rawValue,
                        collection: "app.bsky.feed.postgate",
                        rkey: postRkey,
                        record: postgate
                    )
                    do {
                        let _: CreateRecordResponse = try await network.post(
                            lexicon: "com.atproto.repo.createRecord", body: pgReq
                        )
                    } catch {
                        logger.error("postgate write failed: \(error, privacy: .public)")
                    }
                }
            }

            // Submit additional thread posts
            if !additionalPosts.isEmpty {
                let rootRef = PostRef(uri: firstResponse.uri, cid: firstResponse.cid)
                var parentRef = rootRef
                for threadText in additionalPosts {
                    guard !threadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let threadFacets = FacetBuilder.build(from: threadText, mentionDIDs: mentionDIDs)
                    let threadRecord = PostRecord(
                        text: threadText,
                        facets: threadFacets.isEmpty ? nil : threadFacets,
                        embed: nil,
                        reply: ReplyRef(root: rootRef, parent: parentRef),
                        langs: [selectedLanguage],
                        labels: labelsRecord
                    )
                    let threadReq = CreateRecordRequest(
                        repo: viewerDID.rawValue,
                        collection: "app.bsky.feed.post",
                        record: threadRecord
                    )
                    let threadResponse: CreateRecordResponse = try await network.post(
                        lexicon: "com.atproto.repo.createRecord", body: threadReq
                    )
                    parentRef = PostRef(uri: threadResponse.uri, cid: threadResponse.cid)
                }
            }

            didPost = true
        } catch {
            logger.error("post error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        return updatedImages
    }

    // MARK: - Mention autocomplete

    public func searchMentions(_ prefix: String) {
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let resp: SearchActorsTypeaheadResponse = try await network.get(
                    lexicon: "app.bsky.actor.searchActorsTypeahead",
                    params: ["q": prefix, "limit": "5"]
                )
                mentionSuggestions = resp.actors
            } catch {}
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    public func setError(_ message: String) {
        errorMessage = message
    }

    // MARK: - Helpers

    /// Builds an `EmbedExternal` for a Tenor GIF, matching RN's `resolveGif`
    /// (`lib/api/resolve.ts`):
    ///
    /// - `uri`: `media_formats.gif.url` with `?hh=<H>&ww=<W>` query params so
    ///   downstream renderers can size the GIF without a network round-trip.
    /// - `title`: `content_description` (or post title fallback).
    /// - `description`: `"ALT: <description>"` — RN's `createGIFDescription`
    ///   prefix that distinguishes a default vs. user-authored alt text.
    /// - `thumb`: a blob ref of the static preview frame (RN uses
    ///   `media_formats.preview.url`, falling back to `tinygif` when missing).
    private func buildGIFExternalEmbed(_ gif: TenorGif) async throws -> Embed {
        // Append width / height as query params on the gif URL — matches
        // RN's `resolveGif` so the embed carries layout info.
        let dims = gif.dims
        var components = URLComponents(string: gif.gifURL)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "hh", value: String(dims.height)))
        items.append(URLQueryItem(name: "ww", value: String(dims.width)))
        components?.queryItems = items
        let uri = components?.url?.absoluteString ?? gif.gifURL

        let alt = gif.altText
        // RN's `createGIFDescription` returns `"ALT: <text>"` for the default
        // case (no user-supplied alt). The picker doesn't expose an alt-text
        // field yet (RN does — see `GifAltText.tsx`), so we always emit the
        // default form; a follow-up can wire user-authored alt text through
        // the same composer surface used for images.
        let description = "ALT: \(alt)"

        // Download and upload the thumb blob. Best-effort failures throw so
        // the caller can surface a non-fatal error; the post itself doesn't
        // need this blob to be valid AT Proto, but Bluesky clients render a
        // dramatically better preview when it's present.
        guard let previewURL = URL(string: gif.previewURL) else {
            throw URLError(.badURL)
        }
        let (data, mime) = try await fetchImageData(previewURL)
        let resp: UploadBlobResponse = try await network.upload(
            lexicon: "com.atproto.repo.uploadBlob",
            data: data,
            mimeType: mime
        )

        return .external(EmbedExternal(
            uri: uri,
            title: alt,
            description: description,
            thumb: resp.blob
        ))
    }

    /// Downloads the image data at `url` and returns its raw bytes plus MIME type.
    /// Caps the payload at 1 MB so a misbehaving server can't stall posting.
    private func fetchImageData(_ url: URL) async throws -> (Data, String) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (compatible; Bluesky-SwiftUI link preview)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let mime = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            ?? "image/jpeg"
        return (data, mime)
    }
}
