import Foundation
import Observation
import BlueskyCore
import BlueskyKit

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

    // MARK: - Derived

    public var characterCount: Int { text.unicodeScalars.count }
    public var isOverLimit: Bool { characterCount > 300 }
    public var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isOverLimit && !isPosting
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
    }

    // MARK: - Post

    public func post() async {
        guard canPost else { return }
        images = await store.post(
            text: text,
            images: images,
            replyTo: replyTo,
            quotedPost: quotedPost,
            selectedLanguage: selectedLanguage,
            mentionDIDs: mentionDIDs
        )
    }

    // MARK: - Mention autocomplete

    public func onTextChange() {
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
    }

    public func removeImage(id: UUID) {
        images.removeAll { $0.id == id }
    }

    public func clearError() {
        store.clearError()
    }
}
