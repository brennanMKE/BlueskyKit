import Testing
import Foundation
import Observation
@testable import BlueskyComposer
import BlueskyCore
import BlueskyKit

// MARK: - Mocks

// ComposerStoring is declared in BlueskyComposer, which compiles with
// defaultIsolation(MainActor.self), so conformers are @MainActor (same
// pattern as MockBookmarkStore in BlueskyKitTests.swift).
@MainActor
@Observable
private final class MockComposerStore: ComposerStoring {
    var isPosting = false
    var didPost = false
    var errorMessage: String?
    var mentionSuggestions: [ProfileBasic] = []

    /// Actors returned synchronously by `searchMentions` — no debounce, no
    /// network, so tests can assert overlay state deterministically.
    var stubActors: [ProfileBasic] = []
    private(set) var searchedPrefixes: [String] = []
    private(set) var clearMentionSuggestionsCalls = 0

    func post(
        text: String,
        images: [ComposerImageAttachment],
        attachedVideo: VideoAttachment?,
        selectedGIF: TenorGif?,
        detectedURL: URL?,
        linkMetadata: LinkMetadata?,
        additionalPosts: [String],
        replyTo: PostRef?,
        replyRoot: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID],
        selfLabels: Set<String>,
        threadgateAllow: ThreadgateAllowSelection,
        quotesEnabled: Bool
    ) async -> [ComposerImageAttachment] { images }

    func searchMentions(_ prefix: String) {
        searchedPrefixes.append(prefix)
        mentionSuggestions = stubActors
    }

    func clearMentionSuggestions() {
        clearMentionSuggestionsCalls += 1
        mentionSuggestions = []
    }

    func clearError() { errorMessage = nil }
    func setError(_ message: String) { errorMessage = message }
}

private final class MockDraftsStore: DraftsStoring, Sendable {
    func loadAll() async -> [Draft] { [] }
    func save(_ draft: Draft) async {}
    func delete(_ id: UUID) async {}
    func deleteAll() async {}
}

// MARK: - Helpers

private let alice = ProfileBasic(
    did: DID(rawValue: "did:plc:alice"),
    handle: Handle(rawValue: "alice.bsky.social"),
    displayName: "Alice",
    avatar: nil
)

@MainActor
private func makeViewModel() -> (ComposerViewModel, MockComposerStore) {
    let store = MockComposerStore()
    store.stubActors = [alice]
    let vm = ComposerViewModel(store: store, draftsStore: MockDraftsStore())
    return (vm, store)
}

/// Simulate the user typing: set the text and fire the same `onTextChange`
/// the sheet's `.onChange(of: viewModel.text)` fires.
@MainActor
private func type(_ text: String, into vm: ComposerViewModel) {
    vm.text = text
    vm.onTextChange()
}

// MARK: - Tests

@MainActor
@Suite("Composer mention autocomplete trigger/dismiss rules (#0198)")
struct ComposerMentionAutocompleteTests {

    @Test("typing a partial @mention at the end of the text shows suggestions")
    func partialMentionTriggers() {
        let (vm, store) = makeViewModel()

        type("@al", into: vm)

        #expect(vm.mentionPrefix == "al")
        #expect(store.searchedPrefixes == ["al"])
        #expect(!store.mentionSuggestions.isEmpty)
    }

    @Test("typing a space after the handle dismisses the overlay")
    func trailingSpaceDismisses() {
        let (vm, store) = makeViewModel()
        type("@alice", into: vm)
        #expect(vm.mentionPrefix == "alice")
        #expect(!store.mentionSuggestions.isEmpty)

        type("@alice ", into: vm)

        #expect(vm.mentionPrefix == nil)
        #expect(store.mentionSuggestions.isEmpty)
        #expect(store.clearMentionSuggestionsCalls == 1)
    }

    @Test("selecting a suggestion completes the mention and dismisses the overlay")
    func selectionDismisses() {
        let (vm, store) = makeViewModel()
        type("@al", into: vm)
        #expect(!store.mentionSuggestions.isEmpty)

        vm.selectMention(alice)

        #expect(vm.text == "@alice.bsky.social ")
        #expect(vm.mentionPrefix == nil)
        #expect(store.mentionSuggestions.isEmpty)
        #expect(vm.mentionDIDs["alice.bsky.social"] == alice.did)
    }

    @Test("a completed mention does not re-trigger the overlay")
    func completedMentionDoesNotRetrigger() {
        let (vm, store) = makeViewModel()
        type("@al", into: vm)
        vm.selectMention(alice)
        #expect(store.searchedPrefixes == ["al"])

        // The text mutation in selectMention fires the sheet's
        // .onChange(of: text) → onTextChange. This is the exact sequence
        // that used to re-set mentionPrefix from the completed handle.
        vm.onTextChange()

        #expect(vm.mentionPrefix == nil)
        #expect(store.mentionSuggestions.isEmpty)
        #expect(store.searchedPrefixes == ["al"])

        // Keep typing unrelated words after the mention — still no overlay.
        // (No URL here: detectURL would kick off a real link-metadata fetch.)
        type("@alice.bsky.social check this out", into: vm)
        #expect(vm.mentionPrefix == nil)
        #expect(store.mentionSuggestions.isEmpty)
        #expect(store.searchedPrefixes == ["al"])
    }

    @Test("an earlier completed mention plus new plain text does not show the overlay")
    func earlierMentionWithPlainTextStaysHidden() {
        let (vm, store) = makeViewModel()

        type("hello @alice.bsky.social nice post", into: vm)

        #expect(vm.mentionPrefix == nil)
        #expect(store.searchedPrefixes.isEmpty)
        #expect(store.mentionSuggestions.isEmpty)
    }

    @Test("starting a second mention later re-triggers the overlay")
    func secondMentionRetriggers() {
        let (vm, store) = makeViewModel()
        type("@al", into: vm)
        vm.selectMention(alice)

        type("@alice.bsky.social hi @b", into: vm)

        #expect(vm.mentionPrefix == "b")
        #expect(store.searchedPrefixes == ["al", "b"])
        #expect(!store.mentionSuggestions.isEmpty)
    }

    @Test("punctuation terminates the mention token (RN getMentionAt charset)")
    func punctuationTerminatesToken() {
        let (vm, store) = makeViewModel()
        type("@alice", into: vm)
        #expect(vm.mentionPrefix == "alice")

        type("@alice!", into: vm)

        #expect(vm.mentionPrefix == nil)
        #expect(store.mentionSuggestions.isEmpty)
    }

    @Test("selectMention replaces the trailing token, not an earlier identical word")
    func selectionReplacesTrailingOccurrence() {
        let (vm, store) = makeViewModel()
        type("@al was typed before @al", into: vm)
        #expect(vm.mentionPrefix == "al")

        vm.selectMention(alice)

        #expect(vm.text == "@al was typed before @alice.bsky.social ")
        #expect(store.mentionSuggestions.isEmpty)
    }
}
