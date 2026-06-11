import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Notification feed — likes, reposts, follows, mentions, quotes, replies.
public struct NotificationsScreen: View {

    public var onUnreadCountChange: ((Int) -> Void)?
    /// Tap callback for any actor avatar / name in the row (#0080). Mirrors
    /// the `onAuthorTap` callback already used by `FeedView`/`ThreadView` —
    /// the parent (`MainTabView`) sets `feedProfileDID` to push a
    /// `ProfileScreen`. `nil` simply disables the tap.
    public var onAuthorTap: ((ProfileBasic) -> Void)?
    /// Tap callback for the row's post target (the previewed post or the
    /// notification's reason subject). When provided, the parent owns the
    /// navigation destination and can push a real `ThreadView` from
    /// `BlueskyFeed` — `BlueskyNotifications` cannot import `BlueskyFeed`
    /// directly without forming a cross-feature cycle, so this callback
    /// hoists the destination wiring up to the app shell (#0160 / #0062).
    /// When `nil`, the screen falls back to its internal placeholder
    /// `navigationDestination` (used by previews and any callsite that
    /// hasn't wired the real thread view yet).
    public var onPostTap: ((ATURI) -> Void)?
    /// Tap callback for `feedgen-like` notifications, where the
    /// `reasonSubject` is an `app.bsky.feed.generator` AT-URI rather than
    /// a post URI. The parent app shell pushes a `CustomFeedTimelineView`
    /// from `BlueskyFeed` (#0062). When `nil`, falls back to `onPostTap`
    /// so previews and unwired callsites still navigate somewhere — even
    /// if the resulting thread renders empty.
    public var onFeedTap: ((ATURI) -> Void)?
    /// Tap callback for `starterpack-joined` notifications, where the
    /// `reasonSubject` is an `app.bsky.graph.starterpack` AT-URI. The
    /// parent app shell pushes a `StarterPackScreen` from `BlueskyLists`
    /// (#0062). When `nil`, falls back to `onPostTap`.
    public var onStarterPackTap: ((ATURI) -> Void)?

    @State private var viewModel: NotificationsViewModel
    @State private var threadURI: ATURI?
    /// Active segmented-tab filter. Mirrors `viewModel.filter` so the
    /// Picker has a Binding it can drive directly. Cold-starts at `.all`
    /// and is intentionally not persisted across launches (issue #0078).
    @State private var activeFilter: NotificationFilter = .all

    /// Designated initializer taking an externally-owned view model (#0196).
    ///
    /// The app shell owns a single `NotificationsViewModel` whose store
    /// backs the app-wide unread-count poll; passing it here means the
    /// screen's `markSeen()` zeroes the *same* `unreadCount` the tab badge
    /// renders, so opening the tab clears the badge (RN parity:
    /// `markAllRead()` in `state/queries/notifications/unread.tsx`).
    public init(
        viewModel: NotificationsViewModel,
        onUnreadCountChange: ((Int) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil,
        onPostTap: ((ATURI) -> Void)? = nil,
        onFeedTap: ((ATURI) -> Void)? = nil,
        onStarterPackTap: ((ATURI) -> Void)? = nil
    ) {
        self.onUnreadCountChange = onUnreadCountChange
        self.onAuthorTap = onAuthorTap
        self.onPostTap = onPostTap
        self.onFeedTap = onFeedTap
        self.onStarterPackTap = onStarterPackTap
        _viewModel = State(wrappedValue: viewModel)
    }

    /// Convenience initializer that creates a private view model from the
    /// network client. Used by previews and callsites that don't share
    /// unread-count state with an app shell — the badge-clearing path only
    /// works app-wide through the `viewModel:` initializer above.
    public init(
        network: any NetworkClient,
        onUnreadCountChange: ((Int) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil,
        onPostTap: ((ATURI) -> Void)? = nil,
        onFeedTap: ((ATURI) -> Void)? = nil,
        onStarterPackTap: ((ATURI) -> Void)? = nil
    ) {
        self.init(
            viewModel: NotificationsViewModel(network: network),
            onUnreadCountChange: onUnreadCountChange,
            onAuthorTap: onAuthorTap,
            onPostTap: onPostTap,
            onFeedTap: onFeedTap,
            onStarterPackTap: onStarterPackTap
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            NotificationsFilterStrip(selection: $activeFilter)
            Group {
                if viewModel.notifications.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.notifications.isEmpty, let msg = viewModel.errorMessage {
                    errorView(msg)
                } else if viewModel.notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationList
                }
            }
        }
        #if os(macOS)
        .navigationTitle("Notifications")
        #else
        // iOS top chrome is owned by the parent — `MainTabView` mounts a
        // slim `BlueskyTopBar` above this view on iPhone; using inline
        // display mode here suppresses the giant "Notifications" headline
        // the system nav bar would otherwise draw, while iPad regular
        // keeps the system nav bar (also inline).
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // UI-test anchor for the whole notifications surface (#0180). Applied
        // to the outer VStack so it exists regardless of loading / empty /
        // error / list state.
        .accessibilityIdentifier("notifications-screen")
        .task {
            await viewModel.loadInitial()
            await viewModel.markSeen()
        }
        .onChange(of: activeFilter) { _, newValue in
            // Filter switching is a synchronous flip on the store — both
            // tabs share the same underlying data array, so no refetch.
            viewModel.setFilter(newValue)
        }
        .onChange(of: viewModel.unreadCount) { _, count in
            onUnreadCountChange?(count)
        }
        // Internal placeholder destination — only mounted when the parent
        // hasn't wired its own `onPostTap` (e.g. previews). Real navigation
        // for the app shell goes through the `onPostTap` callback so the
        // app target can mount the real `ThreadView` from `BlueskyFeed`.
        .navigationDestination(isPresented: Binding(
            get: { threadURI != nil && onPostTap == nil },
            set: { if !$0 { threadURI = nil } }
        )) {
            if let uri = threadURI {
                Text("Thread: \(uri.rawValue)").navigationTitle("Thread")
            }
        }
    }

    /// Routes a row tap based on the AT-URI's collection segment so
    /// `feedgen-like` and `starterpack-joined` notifications land on the
    /// right destination instead of opening an empty thread (#0062).
    /// Falls back to the post-tap callback (and ultimately the internal
    /// placeholder) when no specialised handler is wired.
    private func handlePostTap(_ uri: ATURI) {
        switch uri.collection {
        case "app.bsky.feed.generator":
            if let onFeedTap {
                onFeedTap(uri)
                return
            }
        case "app.bsky.graph.starterpack":
            if let onStarterPackTap {
                onStarterPackTap(uri)
                return
            }
        default:
            break
        }
        if let onPostTap {
            onPostTap(uri)
        } else {
            threadURI = uri
        }
    }

    // MARK: - List

    private var notificationList: some View {
        let groups = viewModel.groupedNotifications
        return List {
            ForEach(groups) { group in
                GroupedNotificationRow(
                    group: group,
                    postCache: viewModel.postCache,
                    onTap: { uri in handlePostTap(uri) },
                    onAuthorTap: { profile in onAuthorTap?(profile) }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    if group.id == groups.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Empty / Error

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: activeFilter == .mentions ? "at" : "bell")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(activeFilter == .mentions ? "No mentions yet" : "No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter strip

/// Two-segment selector — All / Mentions — matching the React Native
/// reference styling (#0078). Uses a brand-color 2pt underline for the
/// selected segment instead of the iOS-default segmented control look,
/// for visual parity with the Home feed tab strip introduced in #0074.
private struct NotificationsFilterStrip: View {

    @Environment(\.blueskyTheme) private var theme
    @Binding var selection: NotificationFilter

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(.all, label: "All")
            segmentButton(.mentions, label: "Mentions")
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .background(theme.colors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)
        }
        // UI-test anchor for the All / Mentions filter strip (#0180).
        .accessibilityIdentifier("notifications-filter-strip")
    }

    private func segmentButton(_ value: NotificationFilter, label: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Grouped notification row

private struct GroupedNotificationRow: View {
    let group: GroupedNotification
    /// Provides the resolved `PostView` (or loading state) for the row's
    /// `previewPostURI`. Reading from `@Observable` cache here means each
    /// row re-renders when the cache resolves its URI — no manual diffing.
    let postCache: NotificationPostCache
    let onTap: (ATURI) -> Void
    /// Tap callback for any actor avatar (in the stack) or any actor row
    /// (in the expanded list) — wires through to the screen's
    /// `onAuthorTap` so the parent can push `ProfileScreen` (#0080).
    let onAuthorTap: (ProfileBasic) -> Void

    /// Theme palette — used for the brand-color filled bell on unread
    /// rows (#0082).
    @Environment(\.blueskyTheme) private var theme

    /// Maximum number of actor avatars rendered in the collapsed stack;
    /// excess actors collapse behind a chevron-down expand button (#0080).
    private static let collapsedAvatarLimit = 5

    /// Drives the chevron-down → list expansion (#0080). Local to the row
    /// so each group expands independently; resets when the row is recycled.
    @State private var isExpanded: Bool = false

    var body: some View {
        // Branch on reason at the top so each layout stays simple (#0081).
        // Reply rows get a distinct shape (responder avatar leading, a
        // "↳ Replied to you" indicator, then the reply body) — RN drops the
        // bell + avatar-stack chrome on this variant. Quote and mention
        // remain on the default grouped layout: RN renders all three as a
        // full Post card, but the simplified "Replied to you" affordance
        // only reads correctly for replies, so we don't generalize it.
        Group {
            if group.reason == "reply" {
                replyRow
            } else {
                defaultGroupedRow
            }
        }
        // UI-test anchors (#0180). The row carries `notification-cell` but uses
        // `.accessibilityElement(children: .contain)` so its child static texts
        // (actor summary, reason text, timestamp) stay individually queryable —
        // applying an identifier *and* a value would fold the subtree into a
        // single combined element and hide that text from the #0063
        // raw-reason-leak guard. The raw `reason` code is exposed via a
        // separate zero-size marker (`notification-reason-<reason>`) the
        // tap-routing tests use to pick a like/repost row (→ thread) vs. a
        // follow row (→ profile) without coupling to row layout. Multi-actor
        // groups also drop a `notifications-group-header` marker, locking in
        // the grouping regression (#0029) without stealing the row's tappable
        // `notification-cell` identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notification-cell")
        .overlay(alignment: .topLeading) {
            ZStack {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("notification-reason-\(group.reason)")
                if group.actors.count >= 2 {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("notifications-group-header")
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Default grouped row (likes, reposts, follows, mentions, quotes, …)

    private var defaultGroupedRow: some View {
        // Outer container is a plain VStack rather than a `Button` because
        // the row now contains *multiple* tap targets (the post body, each
        // avatar, the expand chevron, each expanded actor row). Wrapping
        // everything in a single Button would consume the inner taps. The
        // body area itself is given a `contentShape` + `onTapGesture` so
        // tapping the post region still navigates to the thread.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                reasonIcon
                VStack(alignment: .leading, spacing: 4) {
                    actorAvatarRow
                    HStack(spacing: 4) {
                        Text(actorSummary)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(2)
                        if !group.isRead {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(reasonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    postPreview
                }
                Spacer()
                Text(RelativeTimeFormatter.string(from: group.indexedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            // Expanded actor list — slides down below the row when the
            // chevron is tapped. Uses a `clipped` outer to hide the
            // overflow during the height animation.
            if isExpanded {
                expandedActorList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap target prefers the previewed post (the actor's reply or
            // the viewer's own post that was liked), falling back to the
            // older `reasonSubject` so non-post reasons still navigate.
            if let target = group.previewPostURI ?? group.reasonSubject {
                onTap(target)
            }
        }
        .animation(.smooth, value: isExpanded)
    }

    // MARK: - Reply row (#0081)

    /// Reply-only variant: full-size responder avatar at the leading edge,
    /// a "↳ Replied to you" indicator, then the actor identity and the
    /// inline reply body. Drops the bell icon and avatar stack — RN only
    /// shows those on the grouped variants. Reply groups are always
    /// single-actor after #0079's grouping change (each reply is keyed by
    /// its own notification `uri`), so there's no stack to render anyway.
    private var replyRow: some View {
        let actor = group.actors.first
        return HStack(alignment: .top, spacing: 12) {
            // Leading: full-size avatar (~40pt) at the row's left edge.
            // Tappable so it routes to the actor's profile, mirroring the
            // avatar-stack behavior on the default layout.
            if let actor {
                Button {
                    onAuthorTap(actor)
                } label: {
                    AvatarView(
                        url: actor.avatar,
                        handle: actor.handle.rawValue,
                        size: 40
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actor.displayName ?? "@\(actor.handle.rawValue)")
            }
            VStack(alignment: .leading, spacing: 2) {
                // First line: small "↳ Replied to you" indicator. Uses the
                // literal arrow glyph (rather than an SF Symbol) so the row
                // matches the RN reference exactly — caption2, secondary.
                HStack(spacing: 4) {
                    Text("↳ Replied to you")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !group.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                // Second line: responder name, handle, timestamp.
                if let actor {
                    HStack(spacing: 4) {
                        Text(actor.displayName ?? actor.handle.rawValue)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Text("@\(actor.handle.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        Text("·")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Text(RelativeTimeFormatter.string(from: group.indexedAt))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                // Body: the reply post text (rendered inline per #0079).
                postPreview
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // For replies, `previewPostURI` is the actor's reply URI; the
            // existing tap handler routes it to the thread (per #0062).
            if let target = group.previewPostURI ?? group.reasonSubject {
                onTap(target)
            }
        }
    }

    // MARK: - Inline post preview

    /// Inline post-content excerpt rendered below the reason text on
    /// post-related rows (#0079). Skipped entirely for `follow`/`verified`
    /// and other reasons that don't have a `previewPostURI`.
    @ViewBuilder
    private var postPreview: some View {
        if let uri = group.previewPostURI {
            if let post = postCache.post(for: uri) {
                VStack(alignment: .leading, spacing: 6) {
                    PostBodyView(
                        text: post.record.text,
                        facets: post.record.facets,
                        lineLimit: 4
                    )
                    compactLinkCard(for: post.embed)
                }
                .padding(.top, 4)
            } else if postCache.isLoading(uri: uri) {
                postPreviewSkeleton
                    .padding(.top, 4)
            } else if postCache.isMissing(uri: uri) {
                // Server returned no entry (deleted/blocked); render
                // nothing rather than a perpetual placeholder.
                EmptyView()
            } else {
                // Not yet hydrated and not in flight (e.g. cache miss
                // before the screen's first hydrate pass completed). A
                // light skeleton is still the right thing to show.
                postPreviewSkeleton
                    .padding(.top, 4)
            }
        }
    }

    /// Two grayed bars approximating ~2 lines of body text while the
    /// post-fetch is in flight. Deliberately lightweight — keep rows dense.
    private var postPreviewSkeleton: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.15))
                .frame(maxWidth: .infinity)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.15))
                .frame(maxWidth: 220)
                .frame(height: 10)
        }
    }

    /// Compact inline link-card variant for external embeds. Skipped for
    /// image/video/quote embeds — they make rows too tall, and the issue
    /// scope explicitly says to keep notifications dense. Returns the
    /// shortest meaningful card: a single-line title + a single-line URL.
    private func compactLinkCard(for embed: BlueskyCore.EmbedView?) -> AnyView {
        // Resolve the external embed if there is one — including the media
        // half of a `recordWithMedia` composite. Returns `AnyView` because
        // the function is recursive and `some View` would self-infer.
        let external: EmbedExternalView?
        switch embed {
        case .external(let ext):
            external = ext
        case .recordWithMedia(_, let media):
            // recordWithMedia composites a quote + media; surface the
            // external half when present, otherwise no inline card.
            if case .external(let ext) = media {
                external = ext
            } else {
                external = nil
            }
        default:
            external = nil
        }
        guard let ext = external else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    if !ext.title.isEmpty {
                        Text(ext.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(displayHost(for: ext.uri) ?? ext.uri)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
        )
    }

    /// `https://example.com/foo` → `example.com`. Falls back to nil when the
    /// URI doesn't parse, in which case the caller renders the raw URI.
    private func displayHost(for uri: String) -> String? {
        guard let url = URL(string: uri), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Avatar row: up to `collapsedAvatarLimit` overlapping avatars, each
    /// independently tappable, with a chevron-down expand button on the
    /// trailing edge when there are more actors than fit in the stack
    /// (#0080). Avatars overlap by ~30% (negative `HStack` spacing) and
    /// each carries a 1.5pt background-colored ring so the overlap reads
    /// as discrete circles in both light and dark mode.
    private var actorAvatarRow: some View {
        let visible = Array(group.actors.prefix(Self.collapsedAvatarLimit))
        let hasOverflow = group.actors.count > Self.collapsedAvatarLimit
        // -8 against a 28pt avatar = ~28% overlap on the leading edge of
        // each subsequent avatar, matching the RN reference.
        return HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, actor in
                Button {
                    onAuthorTap(actor)
                } label: {
                    AvatarView(
                        url: actor.avatar,
                        handle: actor.handle.rawValue,
                        size: 28
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.uiCompatibleSystemBackground, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actor.displayName ?? "@\(actor.handle.rawValue)")
            }
            if hasOverflow {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.uiCompatibleSystemBackground, lineWidth: 1.5)
                        )
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.smooth, value: isExpanded)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .accessibilityLabel(isExpanded ? "Collapse actor list" : "Expand actor list")
            }
        }
    }

    /// Vertically-stacked list of every actor in the group with full
    /// names — shown when the chevron is expanded (#0080). Each entry is
    /// tappable and routes back through `onAuthorTap`.
    private var expandedActorList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(group.actors.enumerated()), id: \.offset) { _, actor in
                Button {
                    onAuthorTap(actor)
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(
                            url: actor.avatar,
                            handle: actor.handle.rawValue,
                            size: 28
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(actor.displayName ?? actor.handle.rawValue)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("@\(actor.handle.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // Indent to align under the avatar stack (reasonIcon = 24pt
        // wide + 12pt HStack spacing in the parent row).
        .padding(.leading, 36)
        .padding(.top, 8)
    }

    private var reasonIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundStyle(iconColor)
            .frame(width: 24)
    }

    private var iconName: String {
        switch group.reason {
        case "like", "like-via-repost", "feedgen-like":
            return "heart.fill"
        case "repost", "repost-via-repost":
            return "arrow.2.squarepath"
        case "follow":
            return "person.fill.badge.plus"
        case "mention":
            return "at"
        case "reply":
            return "bubble.left.fill"
        case "quote":
            return "quote.bubble.fill"
        case "starterpack-joined":
            return "person.2.fill"
        case "subscribed-post":
            return "bell.badge.fill"
        case "contact-match":
            return "person.crop.circle.badge.checkmark"
        case "verified":
            return "checkmark.seal.fill"
        case "unverified":
            return "xmark.seal.fill"
        // Catch-all bell — flips between filled (unread) and outlined
        // (seen) per #0082, mirroring the RN reference.
        default:
            return group.isRead ? "bell" : "bell.fill"
        }
    }

    private var iconColor: Color {
        switch group.reason {
        case "like", "like-via-repost", "feedgen-like":
            return .pink
        case "repost", "repost-via-repost":
            return .green
        case "follow", "starterpack-joined", "contact-match":
            return .blue
        case "verified":
            return .blue
        case "unverified":
            return .orange
        case "subscribed-post":
            return .accentColor
        // Brand-blue when unread, secondary grey when seen (#0082).
        default:
            return group.isRead ? .secondary : theme.colors.link
        }
    }

    /// "Alice", "Alice and 1 other", "Alice and 4 others" — matches the
    /// RN reference (#0080). Multi-actor groups always read as
    /// "{first} and N others" rather than enumerating multiple names so
    /// the row stays compact; the full list is one tap away on the
    /// expand chevron.
    private var actorSummary: String {
        let actors = group.actors
        let name: (ProfileBasic) -> String = { a in
            a.displayName ?? "@\(a.handle.rawValue)"
        }
        switch actors.count {
        case 0:  return ""
        case 1:  return name(actors[0])
        default:
            let extra = actors.count - 1
            return "\(name(actors[0])) and \(extra) other\(extra == 1 ? "" : "s")"
        }
    }

    private var reasonText: String {
        switch group.reason {
        case "like":               return "liked your post"
        case "repost":             return "reposted your post"
        case "follow":             return "followed you"
        case "mention":            return "mentioned you"
        case "reply":              return "replied to your post"
        case "quote":              return "quoted your post"
        case "like-via-repost":    return "liked your repost"
        case "repost-via-repost":  return "reposted your repost"
        case "feedgen-like":       return "liked your custom feed"
        case "starterpack-joined": return "joined via your starter pack"
        case "subscribed-post":    return "shared a new post"
        case "contact-match":      return "is in your contacts"
        case "verified":           return "verified you"
        case "unverified":         return "removed your verification"
        default:                   return group.reason
        }
    }
}

// MARK: - Platform color helper

private extension Color {
    /// `UIColor.systemBackground` on iOS, `NSColor.windowBackgroundColor` on macOS.
    static var uiCompatibleSystemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - Previews

#Preview("NotificationsScreen — Light") {
    NavigationStack {
        NotificationsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("NotificationsScreen — Dark") {
    NavigationStack {
        NotificationsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
