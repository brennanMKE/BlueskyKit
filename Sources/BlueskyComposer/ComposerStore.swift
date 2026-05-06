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
        detectedURL: URL?,
        linkMetadata: LinkMetadata?,
        additionalPosts: [String],
        replyTo: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID]
    ) async -> [ComposerImageAttachment]
    func searchMentions(_ prefix: String)
    func clearError()
    func setError(_ message: String)
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
        detectedURL: URL?,
        linkMetadata: LinkMetadata?,
        additionalPosts: [String],
        replyTo: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID]
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
            let record = PostRecord(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                embed: embed,
                reply: reply,
                langs: [selectedLanguage]
            )
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.feed.post",
                record: record
            )
            let firstResponse: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )

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
                        langs: [selectedLanguage]
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
