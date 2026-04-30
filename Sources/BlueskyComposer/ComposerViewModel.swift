import Foundation
import Observation
import BlueskyCore
import BlueskyKit
#if os(iOS)
import PhotosUI
#endif

@Observable
public final class ComposerViewModel {

    // MARK: - Delegated from store

    public var isPosting: Bool { store.isPosting }
    public var didPost: Bool { store.didPost }
    public var errorMessage: String? { store.errorMessage }
    public var mentionSuggestions: [ProfileBasic] { store.mentionSuggestions }

    // MARK: - Compose state (view-specific)

    public var text: String = ""
    public var selectedLanguage: String = "en"
    public var images: [ComposerImageAttachment] = []

    public var replyTo: PostRef?
    public var replyToView: PostView?
    public var quotedPost: PostRef?
    public var quotedPostView: PostView?

    public var mentionPrefix: String?
    public var mentionDIDs: [String: DID] = [:]

    // MARK: - Video attachment

    public var attachedVideo: VideoAttachment?

    // MARK: - Link card

    public var detectedURL: URL?
    public var linkCardDismissed: Bool = false

    /// The URL shown in the link card preview (nil when dismissed or images are attached).
    public var visibleLinkURL: URL? {
        guard !linkCardDismissed, images.isEmpty, attachedVideo == nil else { return nil }
        return detectedURL
    }

    // MARK: - Thread / multi-post

    public var additionalPosts: [String] = []

    // MARK: - Derived

    public var characterCount: Int { text.unicodeScalars.count }
    public var isOverLimit: Bool { characterCount > 300 }
    public var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isOverLimit && !isPosting
    }

    // MARK: - Draft key

    private var draftKey: String {
        if let replyTo {
            return "composer.draft.reply.\(replyTo.uri.rawValue)"
        }
        return "composer.draft.text"
    }

    // MARK: - Store

    private let store: any ComposerStoring

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil
    ) {
        self.store = ComposerStore(network: network, accountStore: accountStore)
        self.replyTo = replyTo
        self.replyToView = replyToView
        self.quotedPost = quotedPost
        self.quotedPostView = quotedPostView
        // Restore saved draft
        self.text = UserDefaults.standard.string(forKey: draftKey) ?? ""
    }

    // MARK: - Post

    public func post() async {
        guard canPost else { return }
        images = await store.post(
            text: text,
            images: images,
            attachedVideo: attachedVideo,
            detectedURL: visibleLinkURL,
            additionalPosts: additionalPosts,
            replyTo: replyTo,
            quotedPost: quotedPost,
            selectedLanguage: selectedLanguage,
            mentionDIDs: mentionDIDs
        )
        if store.didPost {
            clearDraft()
        }
    }

    // MARK: - Mention autocomplete

    public func onTextChange() {
        saveDraft()
        detectURL()
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let currentWord = words.last(where: { $0.hasPrefix("@") && $0.count > 1 })
        if let word = currentWord {
            let prefix = String(word.dropFirst())
            if prefix != mentionPrefix {
                mentionPrefix = prefix
                store.searchMentions(prefix)
            }
        } else {
            mentionPrefix = nil
        }
    }

    public func selectMention(_ actor: ProfileBasic) {
        guard let prefix = mentionPrefix else { return }
        let handle = actor.handle.rawValue
        mentionDIDs[handle] = actor.did
        if let range = text.range(of: "@\(prefix)") {
            text.replaceSubrange(range, with: "@\(handle) ")
        }
        mentionPrefix = nil
    }

    // MARK: - Image management

    public func addImage(data: Data, mimeType: String) {
        guard images.count < 4 else { return }
        images.append(ComposerImageAttachment(data: data, mimeType: mimeType))
        // Attaching images clears any pending link card
        linkCardDismissed = false
    }

    public func removeImage(id: UUID) {
        images.removeAll { $0.id == id }
    }

    // MARK: - Video attachment

#if os(iOS)
    public func attachVideo(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
        attachedVideo = VideoAttachment(data: data, mimeType: mimeType)
    }
#endif

    public func removeVideo() {
        attachedVideo = nil
    }

    // MARK: - Link card

    private func detectURL() {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let found = matches.first?.url
        if found != detectedURL {
            detectedURL = found
            linkCardDismissed = false
        }
    }

    public func dismissLinkCard() {
        linkCardDismissed = true
    }

    // MARK: - Thread management

    public func addPostToThread() {
        additionalPosts.append("")
    }

    public func removePost(at index: Int) {
        guard additionalPosts.indices.contains(index) else { return }
        additionalPosts.remove(at: index)
    }

    // MARK: - Draft persistence

    public func saveDraft() {
        UserDefaults.standard.set(text, forKey: draftKey)
    }

    public func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    public func clearError() {
        store.clearError()
    }
}
