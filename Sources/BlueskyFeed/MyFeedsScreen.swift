import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

// MARK: - MyFeedsScreen

/// Destination for the iOS Home top bar's `#` button (#0072 / #0073).
///
/// The screen is the canonical home for managing custom feeds — pinned and
/// saved feeds, suggested feeds, and a search/discovery entry point — and it
/// mirrors the React Native `Feeds.tsx` layout. It owns three sections, each
/// driven by its own store:
///
/// 1. **Search bar** — type-ahead against `app.bsky.unspecced.getPopularFeedGenerators`,
///    backed by `SuggestedFeedsStore.search`. Tapping a result opens the feed.
/// 2. **My Feeds** — pinned (with pin indicator) + saved-but-unpinned, sourced
///    from `SavedFeedsStore` (preferences). Pin/unpin via tap, reorder pinned
///    via `↑↓` buttons (cross-platform — see Gotchas in the issue), swipe-to-
///    unpin saved rows. Persists via `app.bsky.actor.putPreferences`.
/// 3. **Discover new feeds** — curated suggested feeds from
///    `app.bsky.feed.getSuggestedFeeds`, with `+ Add` to add to saved (unpinned).
///
/// Tapping any feed pushes a `CustomFeedTimelineView` for the selected feed
/// URI via the `onFeedTap` callback. Tapping a saved-feed `following` entry
/// closes the screen and lets the caller route back to the timeline.
public struct MyFeedsScreen: View {

    @State private var savedFeedsViewModel: SavedFeedsViewModel
    @State private var suggestedStore: SuggestedFeedsStore
    @State private var searchText: String = ""
    @State private var hasUnsavedChanges = false
    @State private var pendingSave: Task<Void, Never>?

    private let network: any NetworkClient
    private let onFeedTap: ((SavedFeed, GeneratorView?) -> Void)?
    private let onSuggestedTap: ((GeneratorView) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(
        network: any NetworkClient,
        cache: any CacheStore,
        onFeedTap: ((SavedFeed, GeneratorView?) -> Void)? = nil,
        onSuggestedTap: ((GeneratorView) -> Void)? = nil
    ) {
        self.network = network
        self.onFeedTap = onFeedTap
        self.onSuggestedTap = onSuggestedTap
        _savedFeedsViewModel = State(initialValue: SavedFeedsViewModel(network: network, cache: cache))
        _suggestedStore = State(initialValue: SuggestedFeedsStore(network: network))
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                searchSection
                myFeedsSection
                discoverSection
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("My Feeds")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await savedFeedsViewModel.load()
            await suggestedStore.loadSuggested()
            await suggestedStore.resolve(uris: savedFeedsViewModel.feeds.map { $0.value })
        }
        .onChange(of: savedFeedsViewModel.feeds.map { $0.value }) { _, newURIs in
            Task { await suggestedStore.resolve(uris: newURIs) }
        }
    }

    // MARK: - Search section

    private var searchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.textSecondary)
                TextField("Search feeds", text: $searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: searchText) { _, newValue in
                        // Debounced search — 250ms feels live without
                        // hammering the endpoint per keystroke.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            guard searchText == newValue else { return }
                            await suggestedStore.search(query: newValue)
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        suggestedStore.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.backgroundSecondary)
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            if !searchText.isEmpty {
                searchResults
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if suggestedStore.isSearching {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, Spacing.md)
        } else if suggestedStore.searchResults.isEmpty {
            Text("No matches")
                .font(Typography.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
        } else {
            VStack(spacing: 0) {
                ForEach(suggestedStore.searchResults, id: \.uri) { feed in
                    FeedCard(feed: feed) { tapped in
                        onSuggestedTap?(tapped)
                    }
                    Divider()
                }
            }
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - My Feeds section

    private var myFeedsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("My Feeds", trailing: {
                if hasUnsavedChanges {
                    AnyView(
                        Button("Save") { triggerSave() }
                            .font(Typography.bodySmall.weight(.semibold))
                            .foregroundStyle(theme.colors.link)
                            .disabled(savedFeedsViewModel.isSaving)
                    )
                } else {
                    AnyView(EmptyView())
                }
            })

            if savedFeedsViewModel.isLoading && savedFeedsViewModel.feeds.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, Spacing.lg)
            } else if savedFeedsViewModel.feeds.isEmpty {
                Text("Feeds you save will appear here.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.lg)
            } else {
                let pinned = savedFeedsViewModel.feeds.filter(\.pinned)
                let unpinned = savedFeedsViewModel.feeds.filter { !$0.pinned }
                ForEach(Array(pinned.enumerated()), id: \.element.id) { index, feed in
                    savedFeedRow(
                        feed: feed,
                        canMoveUp: index > 0,
                        canMoveDown: index < pinned.count - 1
                    )
                    Divider()
                }
                ForEach(unpinned, id: \.id) { feed in
                    savedFeedRow(feed: feed, canMoveUp: false, canMoveDown: false)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func savedFeedRow(feed: SavedFeed, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        let resolved = suggestedStore.resolvedFeeds[feed.value]
        Button {
            onFeedTap?(feed, resolved)
        } label: {
            HStack(spacing: Spacing.sm) {
                Group {
                    if feed.type == "feed" {
                        AvatarView(
                            url: resolved?.avatar,
                            handle: resolved?.displayName ?? displayName(for: feed),
                            size: 36
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.colors.backgroundSecondary)
                            Image(systemName: iconName(for: feed))
                                .foregroundStyle(theme.colors.link)
                        }
                        .frame(width: 36, height: 36)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved?.displayName ?? displayName(for: feed))
                        .font(Typography.headline)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if let creator = resolved?.creator.handle.rawValue {
                        Text("by @\(creator)")
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    } else {
                        Text(feed.type.capitalized)
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                Spacer(minLength: 0)

                if feed.pinned {
                    // Reorder controls live next to the pin indicator on
                    // pinned rows. `↑↓` buttons are used in place of
                    // drag-to-reorder so the same UI works on iOS and macOS
                    // (SwiftUI drag-to-reorder is finicky on macOS).
                    HStack(spacing: 2) {
                        reorderButton(systemImage: "arrow.up", enabled: canMoveUp) {
                            movePinned(id: feed.id, by: -1)
                        }
                        reorderButton(systemImage: "arrow.down", enabled: canMoveDown) {
                            movePinned(id: feed.id, by: 1)
                        }
                    }
                }

                Button {
                    savedFeedsViewModel.togglePin(id: feed.id)
                    hasUnsavedChanges = true
                } label: {
                    Image(systemName: feed.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(feed.pinned ? Color.orange : theme.colors.textSecondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feed.pinned ? "Unpin" : "Pin")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !feed.pinned {
                Button(role: .destructive) {
                    removeSaved(id: feed.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } else {
                Button {
                    savedFeedsViewModel.togglePin(id: feed.id)
                    hasUnsavedChanges = true
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
                .tint(Color.orange)
            }
        }
        #endif
    }

    private func reorderButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? theme.colors.textPrimary : theme.colors.textTertiary.opacity(0.5))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemImage == "arrow.up" ? "Move up" : "Move down")
    }

    // MARK: - Discover section

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Discover new feeds", trailing: { AnyView(EmptyView()) })

            if suggestedStore.isLoadingSuggested && suggestedStore.suggested.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, Spacing.lg)
            } else if suggestedStore.suggested.isEmpty {
                Text("No suggestions available right now.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.lg)
            } else {
                ForEach(suggestedStore.suggested, id: \.uri) { feed in
                    discoverRow(feed: feed)
                    Divider()
                }
            }
        }
    }

    private func discoverRow(feed: GeneratorView) -> some View {
        let isAlreadySaved = savedFeedsViewModel.feeds.contains {
            $0.value == feed.uri.rawValue
        }
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Button {
                onSuggestedTap?(feed)
            } label: {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    AvatarView(
                        url: feed.avatar,
                        handle: feed.displayName,
                        size: 44
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: Spacing._2xs) {
                        Text(feed.displayName)
                            .font(Typography.headline)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                        Text("by @\(feed.creator.handle.rawValue)")
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                        if let desc = feed.description, !desc.isEmpty {
                            Text(desc)
                                .font(Typography.bodySmall)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(2)
                        }
                        if let likeCount = feed.likeCount, likeCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart")
                                    .font(.system(size: 11))
                                Text(abbreviate(likeCount))
                                    .font(Typography.footnote)
                            }
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.top, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                addSuggested(feed: feed)
            } label: {
                Label(isAlreadySaved ? "Added" : "Add", systemImage: isAlreadySaved ? "checkmark" : "plus")
                    .labelStyle(.titleAndIcon)
                    .font(Typography.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isAlreadySaved
                                  ? theme.colors.backgroundSecondary
                                  : theme.colors.link.opacity(0.15))
                    )
                    .foregroundStyle(isAlreadySaved ? theme.colors.textSecondary : theme.colors.link)
            }
            .buttonStyle(.plain)
            .disabled(isAlreadySaved)
            .accessibilityLabel(isAlreadySaved ? "Already added" : "Add feed")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, trailing: () -> AnyView) -> some View {
        HStack {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private func iconName(for feed: SavedFeed) -> String {
        switch feed.type {
        case "timeline": return "house"
        case "list":     return "list.bullet"
        default:         return "sparkles"
        }
    }

    private func displayName(for feed: SavedFeed) -> String {
        switch feed.type {
        case "timeline": return "Following"
        case "list":     return "List"
        default:         return "Feed"
        }
    }

    private func movePinned(id: String, by offset: Int) {
        var feeds = savedFeedsViewModel.feeds
        let pinned = feeds.filter(\.pinned)
        let unpinned = feeds.filter { !$0.pinned }
        guard let idx = pinned.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + offset
        guard target >= 0, target < pinned.count else { return }
        var reordered = pinned
        let item = reordered.remove(at: idx)
        reordered.insert(item, at: target)
        feeds = reordered + unpinned
        savedFeedsViewModel.feeds = feeds
        hasUnsavedChanges = true
    }

    private func removeSaved(id: String) {
        savedFeedsViewModel.feeds.removeAll { $0.id == id }
        hasUnsavedChanges = true
    }

    private func addSuggested(feed: GeneratorView) {
        let alreadySaved = savedFeedsViewModel.feeds.contains { $0.value == feed.uri.rawValue }
        guard !alreadySaved else { return }
        let entry = SavedFeed(
            id: UUID().uuidString,
            type: "feed",
            value: feed.uri.rawValue,
            pinned: false
        )
        savedFeedsViewModel.feeds.append(entry)
        // Resolve metadata on the fly so the just-added row renders with the
        // real name/avatar even though it came from `getSuggestedFeeds`.
        suggestedStore.noteResolved(feed, for: feed.uri.rawValue)
        hasUnsavedChanges = true
        // Suggested-feed adds save immediately — RN parity.
        triggerSave()
    }

    private func triggerSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            await savedFeedsViewModel.save()
            if !Task.isCancelled {
                hasUnsavedChanges = false
                // Let listeners (the Home `FeedView` tab strip in #0074)
                // know the pinned-feed set has changed so they can re-load
                // from `app.bsky.actor.getPreferences` without forcing the
                // user to re-enter the screen.
                NotificationCenter.default.post(
                    name: .savedFeedsChanged,
                    object: nil
                )
            }
        }
    }

    private func abbreviate(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return "\(n / 1_000)K" }
        return "\(n / 1_000_000)M"
    }
}

// MARK: - Preview helpers

private final class PreviewMyFeedsNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewMyFeedsCache: CacheStore, @unchecked Sendable {
    nonisolated func store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws {}
    nonisolated func fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>? { nil }
    nonisolated func evict(for key: String) async throws {}
    nonisolated func evictAll() async throws {}
}

#Preview("MyFeedsScreen — Light") {
    NavigationStack {
        MyFeedsScreen(
            network: PreviewMyFeedsNetwork(),
            cache: PreviewMyFeedsCache()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("MyFeedsScreen — Dark") {
    NavigationStack {
        MyFeedsScreen(
            network: PreviewMyFeedsNetwork(),
            cache: PreviewMyFeedsCache()
        )
    }
    .preferredColorScheme(.dark)
}
