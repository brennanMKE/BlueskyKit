import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit
#if os(iOS)
import PhotosUI
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ComposerViewModel")

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
    public var linkMetadata: LinkMetadata?
    public var isFetchingLinkMetadata: Bool = false
    private var linkFetchTask: Task<Void, Never>?
    private let linkFetcher = LinkMetadataFetcher()

    /// The URL shown in the link card preview (nil when dismissed or images are attached).
    public var visibleLinkURL: URL? {
        guard !linkCardDismissed, images.isEmpty, attachedVideo == nil else { return nil }
        return detectedURL
    }

    /// Metadata to render in the visible link card, if any.
    public var visibleLinkMetadata: LinkMetadata? {
        guard let visibleLinkURL else { return nil }
        guard let linkMetadata, linkMetadata.url == visibleLinkURL else { return nil }
        return linkMetadata
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
            linkMetadata: visibleLinkMetadata,
            additionalPosts: additionalPosts,
            replyTo: replyTo,
            quotedPost: quotedPost,
            selectedLanguage: selectedLanguage,
            mentionDIDs: mentionDIDs
        )
        if store.didPost {
            clearDraft()
            // Reset transient state so the sheet closes cleanly without leaking
            // composed content into the next session. Importantly, clear `text`
            // BEFORE the sheet's onChange/onDisappear hooks fire — otherwise
            // saveDraft() would re-persist the just-posted text and the next
            // composer open would restore it.
            text = ""
            images = []
            additionalPosts = []
            attachedVideo = nil
            linkMetadata = nil
            detectedURL = nil
            mentionPrefix = nil
            mentionDIDs = [:]
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
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            logger.error("attachVideo: loadTransferable failed: \(error.localizedDescription, privacy: .public)")
            store.setError("Could not load video: \(error.localizedDescription)")
            return
        }
        guard let data else {
            store.setError("Could not load the selected video.")
            return
        }
        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
        attachedVideo = VideoAttachment(data: data, mimeType: mimeType)
    }
#endif

    public func removeVideo() {
        attachedVideo = nil
    }

    // MARK: - Link card

    private func detectURL() {
        // NSDataDetector init only fails for invalid type masks; the static .link mask
        // is valid by construction. If this ever fires it's a programmer error.
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            logger.fault("NSDataDetector init failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            assertionFailure("NSDataDetector init failed: \(error)")
            return
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let found = matches.first?.url
        if found != detectedURL {
            detectedURL = found
            linkCardDismissed = false
            linkMetadata = nil
            linkFetchTask?.cancel()
            if let url = found {
                isFetchingLinkMetadata = true
                let fetcher = linkFetcher
                linkFetchTask = Task { @MainActor [weak self] in
                    let meta = await fetcher.fetch(url)
                    guard let self, !Task.isCancelled else { return }
                    // Only apply if URL hasn't changed.
                    if self.detectedURL == url {
                        self.linkMetadata = meta
                    }
                    self.isFetchingLinkMetadata = false
                }
            } else {
                isFetchingLinkMetadata = false
            }
        }
    }

    public func dismissLinkCard() {
        linkCardDismissed = true
        linkFetchTask?.cancel()
        isFetchingLinkMetadata = false
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
