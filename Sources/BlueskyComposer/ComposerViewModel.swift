import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ComposerViewModel {

    // MARK: - Compose state

    public var text: String = ""
    public var selectedLanguage: String = "en"
    public var isPosting = false
    public var errorMessage: String?
    public var didPost = false

    // MARK: - Reply context

    public var replyTo: PostRef?
    public var replyToView: PostView?

    // MARK: - Quote post

    public var quotedPost: PostRef?
    public var quotedPostView: PostView?

    // MARK: - Image attachments

    public struct ImageAttachment: Identifiable {
        public let id = UUID()
        public let data: Data
        public let mimeType: String
        public var altText: String = ""
        public var blobRef: BlobRef?
    }

    public var images: [ImageAttachment] = []

    // MARK: - Mention autocomplete

    public var mentionSuggestions: [ProfileBasic] = []
    public var mentionPrefix: String?
    public var mentionDIDs: [String: DID] = [:]  // handle → DID for resolved mentions

    // MARK: - Derived

    public var characterCount: Int {
        text.unicodeScalars.count
    }

    public var isOverLimit: Bool { characterCount > 300 }

    public var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isOverLimit && !isPosting
    }

    // MARK: - Dependencies

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private var suggestionTask: Task<Void, Never>?

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.replyTo = replyTo
        self.replyToView = replyToView
        self.quotedPost = quotedPost
        self.quotedPostView = quotedPostView
    }

    // MARK: - Post

    public func post() async {
        guard canPost else { return }
        guard let viewerDID = try? await accountStore.loadCurrentDID() else {
            errorMessage = "Not signed in"
            return
        }
        isPosting = true
        defer { isPosting = false }
        errorMessage = nil
        do {
            // Upload images first
            var uploadedImages: [EmbedImage] = []
            for i in images.indices {
                if images[i].blobRef == nil {
                    let resp: UploadBlobResponse = try await network.upload(
                        lexicon: "com.atproto.repo.uploadBlob",
                        data: images[i].data,
                        mimeType: images[i].mimeType
                    )
                    images[i].blobRef = resp.blob
                }
                if let blob = images[i].blobRef {
                    uploadedImages.append(EmbedImage(image: blob, alt: images[i].altText, aspectRatio: nil))
                }
            }

            // Build embed
            var embed: Embed?
            if !uploadedImages.isEmpty, let qp = quotedPost {
                embed = .recordWithMedia(
                    record: EmbedRecordRef(uri: qp.uri, cid: qp.cid),
                    media: .images(uploadedImages)
                )
            } else if !uploadedImages.isEmpty {
                embed = .images(uploadedImages)
            } else if let qp = quotedPost {
                embed = .record(EmbedRecordRef(uri: qp.uri, cid: qp.cid))
            }

            // Build facets
            let facets = FacetBuilder.build(from: text, mentionDIDs: mentionDIDs)

            // Build reply ref
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
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
            )
            didPost = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mention autocomplete

    public func onTextChange() {
        // Detect if cursor is inside a @mention
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let currentWord = words.last(where: { $0.hasPrefix("@") && $0.count > 1 })
        if let word = currentWord {
            let prefix = String(word.dropFirst())
            if prefix != mentionPrefix {
                mentionPrefix = prefix
                searchMentions(prefix)
            }
        } else {
            mentionPrefix = nil
            mentionSuggestions = []
        }
    }

    private func searchMentions(_ prefix: String) {
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

    public func selectMention(_ actor: ProfileBasic) {
        guard let prefix = mentionPrefix else { return }
        // Replace the @prefix token in text with @handle
        let handle = actor.handle.rawValue
        mentionDIDs[handle] = actor.did
        if let range = text.range(of: "@\(prefix)") {
            text.replaceSubrange(range, with: "@\(handle) ")
        }
        mentionSuggestions = []
        mentionPrefix = nil
    }

    // MARK: - Image management

    public func addImage(data: Data, mimeType: String) {
        guard images.count < 4 else { return }
        images.append(ImageAttachment(data: data, mimeType: mimeType))
    }

    public func removeImage(id: UUID) {
        images.removeAll { $0.id == id }
    }
}
