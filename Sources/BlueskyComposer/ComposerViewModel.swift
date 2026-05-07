import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit
#if os(iOS)
import SwiftUI
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
    /// Self-labels (content warnings) the author has attached to this post.
    /// Mirrors RN's `LabelsBtn` state — values come from the curated set
    /// `{"sexual", "nudity", "porn", "graphic-media"}`. The composer
    /// constrains the adult-content trio to a single selection at a time
    /// (matching RN's `updateAdultLabels`); `graphic-media` is independent.
    public var selectedLabels: Set<String> = []

    /// Reply-restriction selection. Defaults to `.everyone`, which omits the
    /// threadgate record entirely. RN models this as `ThreadgateAllowUISetting[]`
    /// in `view/com/composer/threadgate/ThreadgateBtn.tsx`. We collapse the
    /// two exclusive radios ("Everyone" / "Nobody") and the granular
    /// checkboxes into a single value type so impossible combinations
    /// aren't representable.
    public var threadgateAllow: ThreadgateAllowSelection = .everyone

    /// `false` writes a postgate record disabling quotes. Mirrors RN's
    /// "Allow quotes" toggle on the same dialog.
    public var quotesEnabled: Bool = true

    /// Convenience accessor for the threadgate button: `true` when *any*
    /// non-default restriction is in effect, mirroring RN's
    /// `anyoneCanInteract` derived state.
    public var hasInteractionRestrictions: Bool {
        !threadgateAllow.isDefault || !quotesEnabled
    }

    public var replyTo: PostRef?
    public var replyToView: PostView?
    public var quotedPost: PostRef?
    public var quotedPostView: PostView?

    public var mentionPrefix: String?
    public var mentionDIDs: [String: DID] = [:]

    // MARK: - Video attachment

    public var attachedVideo: VideoAttachment?

    // MARK: - GIF attachment

    /// The Tenor GIF the author has selected from `GIFPickerSheet`. Mirrors
    /// RN's `embedDraft.media` slot for `gif`-kind media. Mutually exclusive
    /// with images and video — the toolbar hides the conflicting buttons
    /// when this is non-nil.
    public var selectedGIF: TenorGif?

    // MARK: - Link card

    public var detectedURL: URL?
    public var linkCardDismissed: Bool = false
    public var linkMetadata: LinkMetadata?
    public var isFetchingLinkMetadata: Bool = false
    private var linkFetchTask: Task<Void, Never>?
    private let linkFetcher = LinkMetadataFetcher()

    /// The URL shown in the link card preview (nil when dismissed or images are attached).
    public var visibleLinkURL: URL? {
        guard !linkCardDismissed, images.isEmpty, attachedVideo == nil, selectedGIF == nil else { return nil }
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

    // MARK: - Accessibility — require alt text

    /// `true` when the user has enabled "Require Alt Text" in
    /// Settings → Accessibility. Read once at composer construction time
    /// (matching RN's `useRequireAltTextEnabled()` hook usage in
    /// `view/com/composer/Composer.tsx`, which is read at the top of the
    /// component and held for the compose session).
    public var requireAltText: Bool

    /// Mirrors RN's `missingAltError` (see
    /// `Bluesky-ReactNative/src/view/com/composer/Composer.tsx` — the
    /// `useMemo` block around `requireAltTextEnabled`). Returns the warning
    /// copy when the preference is on AND any attached media is missing
    /// alt text; otherwise `nil`. The exact strings match RN.
    public var altTextWarning: String? {
        guard requireAltText else { return nil }
        if !images.isEmpty, images.contains(where: { $0.altText.isEmpty }) {
            return "One or more images is missing alt text."
        }
        if let gif = selectedGIF, gif.altText.isEmpty {
            return "One or more GIFs is missing alt text."
        }
        if let video = attachedVideo, video.altText.isEmpty {
            return "One or more videos is missing alt text."
        }
        return nil
    }

    // MARK: - Derived

    public var characterCount: Int { text.unicodeScalars.count }
    public var isOverLimit: Bool { characterCount > 300 }
    public var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
            && !isOverLimit
            && !isPosting
            && altTextWarning == nil
    }

    // MARK: - Draft key

    private var draftKey: String {
        if let replyTo {
            return "composer.draft.reply.\(replyTo.uri.rawValue)"
        }
        return "composer.draft.text"
    }

    // MARK: - Drafts list

    /// User-facing drafts list (the "Drafts" button + sheet). Backed by a
    /// `DraftsStoring` so previews and tests can substitute a mock store.
    /// Distinct from the legacy single-slot auto-save under `draftKey` — the
    /// auto-save remains in place to handle force-quits, while the drafts
    /// list is populated explicitly via `saveCurrentAsDraft`.
    public var draftsStore: any DraftsStoring

    /// `true` when the composer was opened from a draft and should overwrite
    /// it on save (rather than appending a new entry). Set by
    /// `loadDraft(_:)`.
    public var editingDraftID: UUID?

    /// Returns `true` when there's any state worth saving as a draft.
    public var hasDraftableContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
            || attachedVideo != nil
            || selectedGIF != nil
            || !additionalPosts.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !selectedLabels.isEmpty
            || !threadgateAllow.isDefault
            || !quotesEnabled
    }

    // MARK: - Store

    private let store: any ComposerStoring

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil,
        draftsStore: (any DraftsStoring)? = nil,
        preferences: (any PreferencesStore)? = nil
    ) {
        self.store = ComposerStore(network: network, accountStore: accountStore)
        self.replyTo = replyTo
        self.replyToView = replyToView
        self.quotedPost = quotedPost
        self.quotedPostView = quotedPostView
        self.draftsStore = draftsStore ?? UserDefaultsDraftsStore()
        self.requireAltText = Self.loadRequireAltText(from: preferences)
        // Restore saved draft
        self.text = UserDefaults.standard.string(forKey: draftKey) ?? ""
    }

    /// Read the "Require Alt Text" preference once at composer construction.
    ///
    /// Prefers the injected `PreferencesStore` so previews / tests can stub
    /// it. When no store is injected (the existing call sites that don't yet
    /// thread `BlueskyEnvironment` through), we fall back to reading the
    /// same JSON-encoded key directly from `UserDefaults.standard` —
    /// `UserDefaultsPreferencesStore` writes to `.standard` defaults via
    /// `JSONEncoder().encode(value)`, so a `Data` decode of `Bool.self`
    /// produces the same value the settings screen wrote. Any read failure
    /// (corruption, type drift) falls back to `false`, matching the
    /// preference's default value in `SettingsViewModel`.
    private static func loadRequireAltText(from preferences: (any PreferencesStore)?) -> Bool {
        let key = "settings.altTextRequired"
        if let preferences {
            do {
                return try preferences.get(Bool.self, for: key) ?? false
            } catch {
                logger.warning("Could not read requireAltText from PreferencesStore: \(error.localizedDescription, privacy: .public). Defaulting to false.")
                return false
            }
        }
        guard let data = UserDefaults.standard.data(forKey: key) else { return false }
        do {
            return try JSONDecoder().decode(Bool.self, from: data)
        } catch {
            logger.warning("Could not decode requireAltText from UserDefaults: \(error.localizedDescription, privacy: .public). Defaulting to false.")
            return false
        }
    }

    // MARK: - Post

    public func post() async {
        guard canPost else { return }
        images = await store.post(
            text: text,
            images: images,
            attachedVideo: attachedVideo,
            selectedGIF: selectedGIF,
            detectedURL: visibleLinkURL,
            linkMetadata: visibleLinkMetadata,
            additionalPosts: additionalPosts,
            replyTo: replyTo,
            quotedPost: quotedPost,
            selectedLanguage: selectedLanguage,
            mentionDIDs: mentionDIDs,
            selfLabels: selectedLabels,
            threadgateAllow: threadgateAllow,
            quotesEnabled: quotesEnabled
        )
        if store.didPost {
            clearDraft()
            // If this compose session originated from a saved draft, drop
            // that draft from the drafts list now that the post has gone
            // out — matches RN's `deleteDraftAfterPost` behavior.
            if let editingDraftID {
                await draftsStore.delete(editingDraftID)
            }
            editingDraftID = nil
            // Reset transient state so the sheet closes cleanly without leaking
            // composed content into the next session. Importantly, clear `text`
            // BEFORE the sheet's onChange/onDisappear hooks fire — otherwise
            // saveDraft() would re-persist the just-posted text and the next
            // composer open would restore it.
            text = ""
            images = []
            additionalPosts = []
            attachedVideo = nil
            selectedGIF = nil
            linkMetadata = nil
            detectedURL = nil
            mentionPrefix = nil
            mentionDIDs = [:]
            selectedLabels = []
            threadgateAllow = .everyone
            quotesEnabled = true
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

    /// Reorder the attached images by moving the entry currently at
    /// `sourceIndex` to be positioned in front of `destinationIndex`. Mirrors
    /// SwiftUI's `Array.move(fromOffsets:toOffset:)` semantics so callers can
    /// pass an `IndexSet`-style destination directly. Used by the composer
    /// image grid's drag-to-reorder and the per-cell "Move left/right"
    /// accessibility affordances. RN's `Gallery` allows reordering by
    /// dispatching `embed_update_image` actions on the image array — we
    /// achieve the same effect by mutating the array in place.
    public func moveImage(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < images.count else { return }
        var clamped = max(0, min(destinationIndex, images.count))
        // SwiftUI move semantics: a destination greater than source means
        // "insert after"; the API expects the post-removal index, so
        // adjust for the removed element below.
        if clamped > sourceIndex { clamped -= 1 }
        guard clamped != sourceIndex else { return }
        let item = images.remove(at: sourceIndex)
        images.insert(item, at: clamped)
    }

    /// Convenience used by the image cell context menu to move the cell one
    /// slot earlier in the grid. No-op when already first.
    public func moveImageEarlier(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        images.swapAt(idx, idx - 1)
    }

    /// Convenience used by the image cell context menu to move the cell one
    /// slot later in the grid. No-op when already last.
    public func moveImageLater(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }), idx < images.count - 1 else { return }
        images.swapAt(idx, idx + 1)
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

    // MARK: - GIF attachment

    /// Set the selected GIF. Clearing competing media slots mirrors RN's
    /// composer state machine: GIF, image, and video are mutually exclusive
    /// (the toolbar already hides conflicting buttons, but we defensively
    /// clear here too in case state is set programmatically).
    public func setGIF(_ gif: TenorGif) {
        selectedGIF = gif
        // GIF is mutually exclusive with images, video, and link card.
        images = []
        attachedVideo = nil
        linkCardDismissed = true
    }

    public func removeGIF() {
        selectedGIF = nil
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

    // MARK: - Drafts list

    /// Persist the current composer state as an entry in the drafts list.
    /// Overwrites the existing draft when `editingDraftID` is set (the user
    /// opened the composer from the drafts list); otherwise appends a new
    /// draft. Image bytes are intentionally not persisted — see #0100
    /// Gotchas.
    public func saveCurrentAsDraft() async {
        let now = Date()
        let id = editingDraftID ?? UUID()
        let createdAt: Date
        if let editingDraftID {
            // Preserve the original creation time when editing.
            let existing = await draftsStore.loadAll().first(where: { $0.id == editingDraftID })
            createdAt = existing?.createdAt ?? now
        } else {
            createdAt = now
        }
        let draft = Draft(
            id: id,
            text: text,
            createdAt: createdAt,
            updatedAt: now,
            replyTo: replyTo?.uri,
            quotedPostURI: quotedPost?.uri,
            selectedLanguages: [selectedLanguage],
            selfLabels: selectedLabels,
            threadgateAllow: ThreadgateAllowSelectionSnapshot(from: threadgateAllow),
            quotesEnabled: quotesEnabled,
            imagePreviews: nil, // image persistence deferred — see #0100 Gotchas
            selectedGIF: selectedGIF,
            additionalPosts: nil // thread-draft persistence deferred — see #0100 Gotchas
        )
        await draftsStore.save(draft)
        editingDraftID = id
    }

    /// Hydrate the composer from a saved draft entry. Mirrors RN's
    /// `useSelectDraftMutation` flow: replace the visible composer state
    /// outright (the user opened a draft to keep working on it). Image
    /// attachments are not restored — see #0100 Gotchas.
    public func loadDraft(_ draft: Draft) {
        text = draft.text
        selectedLanguage = draft.selectedLanguages.first ?? "en"
        selectedLabels = draft.selfLabels
        threadgateAllow = draft.threadgateAllow.toSelection()
        quotesEnabled = draft.quotesEnabled
        selectedGIF = draft.selectedGIF
        editingDraftID = draft.id
        // Drafts intentionally don't persist image attachments yet, so we
        // clear any current ones rather than mixing draft state with stray
        // images from the prior compose session.
        images = []
        attachedVideo = nil
        additionalPosts = []
        linkCardDismissed = false
        detectedURL = nil
        linkMetadata = nil
        // Re-detect URLs in the restored text so the link card can rebuild.
        onTextChange()
    }

    /// Clear the in-progress composer state without persisting anything.
    /// Used when the user picks "Discard" from the cancel-with-content
    /// prompt.
    public func discardCurrentContent() {
        text = ""
        images = []
        attachedVideo = nil
        selectedGIF = nil
        additionalPosts = []
        selectedLabels = []
        threadgateAllow = .everyone
        quotesEnabled = true
        linkCardDismissed = false
        detectedURL = nil
        linkMetadata = nil
        clearDraft()
        editingDraftID = nil
    }

    public func clearError() {
        store.clearError()
    }
}
