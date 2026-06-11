import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

// MARK: - Tree-render constants

/// RN parity constants for the nested-reply tree renderer (#0141).
/// Mirrors `Bluesky-ReactNative/src/screens/PostThread/const.ts` and the
/// `app.bsky.unspecced.getPostThreadV2` `below` cap used for desktop tree
/// view (`TREE_VIEW_BELOW_DESKTOP`). Indent and avatar widths come from
/// the RN `TREE_INDENT` (= `tokens.space.lg` = 16) and `TREE_AVI_WIDTH`
/// (= 24) values.
private enum ThreadTree {
    /// Per-level indent width for the left rail. Matches RN's
    /// `TREE_INDENT + TREE_AVI_WIDTH/2`.
    static let indentUnit: CGFloat = Spacing.lg + (treeAvatarSize / 2)
    /// Avatar width inside a tree row. RN uses `TREE_AVI_WIDTH = 24`.
    static let treeAvatarSize: CGFloat = 24
    /// Width of the connector line stroke.
    static let lineWidth: CGFloat = 2
    /// Maximum depth at which we keep increasing indent. Past this
    /// level, rows continue to render at the cap — this matches RN's
    /// `TREE_VIEW_BELOW_DESKTOP` (= 6) from
    /// `state/queries/usePostThread/const.ts`.
    static let maxDepth: Int = 6
}

/// Renders a post thread — focal post at the top, then a recursively
/// indented tree of replies with vertical connector lines and "Show N
/// more replies" expanders for branches beyond the indentation cap.
public struct ThreadView: View {

    private let uri: ATURI
    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let bookmarks: (any BookmarkStoring)?
    private let onAuthorTap: ((ProfileBasic) -> Void)?
    private let onPostTap: ((PostView) -> Void)?
    /// Tap on the focal post's "X likes" stat — parent pushes `LikedByScreen`.
    /// Wired through callbacks (rather than internal `navigationDestination`)
    /// so the destination screens can be hosted next to existing destinations
    /// in `MainTabView` without `BlueskyFeed` taking a dependency on them.
    /// The actual stat-row UI that fires these is the responsibility of #0146.
    private let onLikedByTap: ((ATURI) -> Void)?
    private let onRepostedByTap: ((ATURI) -> Void)?
    private let onQuotesTap: ((ATURI) -> Void)?

    @State private var viewModel: ThreadViewModel
    @State private var replyTarget: PostView? = nil
    /// URI of a non-focal post (ancestor or reply) tapped by the user; drives in-thread navigation.
    @State private var selectedReplyURI: ATURI? = nil
    /// Whether the "Hidden replies" section is expanded. Collapsed by
    /// default — RN treats threadgate-hidden replies as opt-in for the
    /// reader, since the OP has explicitly chosen to suppress them.
    @State private var showHiddenReplies: Bool = false

    @Environment(\.blueskyTheme) private var theme

    public init(
        uri: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore,
        bookmarks: (any BookmarkStoring)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil,
        onPostTap: ((PostView) -> Void)? = nil,
        onLikedByTap: ((ATURI) -> Void)? = nil,
        onRepostedByTap: ((ATURI) -> Void)? = nil,
        onQuotesTap: ((ATURI) -> Void)? = nil
    ) {
        self.uri = uri
        self.network = network
        self.accountStore = accountStore
        self.bookmarks = bookmarks
        self.onAuthorTap = onAuthorTap
        self.onPostTap = onPostTap
        self.onLikedByTap = onLikedByTap
        self.onRepostedByTap = onRepostedByTap
        self.onQuotesTap = onQuotesTap
        _viewModel = State(wrappedValue: ThreadViewModel(network: network, uri: uri))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.thread == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = viewModel.errorMessage, viewModel.thread == nil {
                errorView(msg)
            } else if let thread = viewModel.thread {
                threadList(thread)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // #0199: theme background on the screen container — the region below
        // the last reply otherwise shows the system background, which is
        // visibly black (not #151D28) under the Dim variant.
        .background(theme.colors.background)
        .navigationTitle("Thread")
        .toolbar { sortToolbar }
        .task { await viewModel.load() }
        .sheet(isPresented: Binding(
            get: { replyTarget != nil },
            set: { if !$0 { replyTarget = nil } }
        )) {
            if let post = replyTarget {
                ComposerSheet(
                    network: network,
                    accountStore: accountStore,
                    replyTo: PostRef(uri: post.uri, cid: post.cid),
                    replyToView: post
                )
            }
        }
    }

    // MARK: - Toolbar

    /// Reply-sort dropdown. Mirrors RN's `HeaderDropdown`
    /// (`Bluesky-ReactNative/src/screens/PostThread/components/HeaderDropdown.tsx`).
    /// Options span the full lexicon set (`hotness`, `most-likes`,
    /// `newest`, `oldest`, `random`) per the issue spec, even though
    /// the live RN screen surfaces only a subset.
    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Reply sorting", selection: sortBinding) {
                    ForEach(ThreadSort.displayOrder, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Reply sorting", systemImage: "slider.horizontal.3")
            }
            .help("Reply sorting")
            // UI-test coupling surface (#0177): the thread suite asserts this
            // control is present so the reply-sort dropdown (#0140) can't
            // silently regress.
            .accessibilityIdentifier("thread-sort-menu")
            .disabled(viewModel.thread == nil)
        }
    }

    private var sortBinding: Binding<ThreadSort> {
        Binding(
            get: { viewModel.sort },
            set: { viewModel.setSort($0) }
        )
    }

    // MARK: - Thread list

    private func threadList(_ node: ThreadViewPost) -> some View {
        let focalURI = focalPostURI(node)
        let threadgateAllow = focalThreadgateAllow(node)
        return ScrollView {
            LazyVStack(spacing: 0) {
                // Ancestors + focal post — flat, no indent. The focal
                // post itself uses `FocalPostCard` for the larger-avatar,
                // full-date, tappable-stat-row treatment (#0146); all
                // other rows in this segment stay on the regular
                // `PostCard`.
                ForEach(linearRows(for: node), id: \.post.uri) { item in
                    if item.post.uri == focalURI {
                        FocalPostCard(
                            item: item,
                            actions: actions(for: item.post, focalURI: focalURI),
                            threadgateAllow: threadgateAllow,
                            onLikedByTap: onLikedByTap,
                            onRepostedByTap: onRepostedByTap,
                            onQuotesTap: onQuotesTap
                        )
                    } else {
                        PostCard(item: item, actions: actions(for: item.post, focalURI: focalURI))
                    }
                    Divider()
                }
                // Replies — recursive tree (#0141).
                replyTree(of: node, focalURI: focalURI)
            }
        }
        // UI-test coupling surface (#0176): the reply-navigation test asserts
        // this identifier exists once the thread has pushed.
        .accessibilityIdentifier("thread-view")
        .refreshable { await viewModel.load() }
        .navigationDestination(item: $selectedReplyURI) { uri in
            ThreadView(
                uri: uri,
                network: network,
                accountStore: accountStore,
                bookmarks: bookmarks,
                onAuthorTap: onAuthorTap,
                onPostTap: onPostTap,
                onLikedByTap: onLikedByTap,
                onRepostedByTap: onRepostedByTap,
                onQuotesTap: onQuotesTap
            )
        }
    }

    /// Extract the focal (root) post URI from the loaded thread node.
    private func focalPostURI(_ node: ThreadViewPost) -> ATURI? {
        guard case .post(let tp) = node else { return nil }
        return tp.post.uri
    }

    /// Extract the focal post's threadgate `allow` rules, if any. Returns
    /// `nil` when no threadgate is present (the default — anyone can
    /// reply); returns the underlying array (which may be empty, meaning
    /// "nobody can reply") otherwise. `FocalPostCard` uses this to drive
    /// the "Who can reply" badge.
    private func focalThreadgateAllow(_ node: ThreadViewPost) -> [ThreadgateAllowRule]? {
        guard case .post(let tp) = node, let record = tp.threadgate?.record else {
            return nil
        }
        return record.allow
    }

    /// Linear (non-tree) rows above the reply list: ancestors (oldest
    /// first) followed by the focal post. Reply rows are rendered
    /// separately by `replyTree(of:focalURI:)` so each one can carry
    /// its tree-depth metadata.
    private func linearRows(for node: ThreadViewPost) -> [FeedViewPost] {
        guard case .post(let tp) = node else { return [] }
        var result = collectAncestors(tp.parent)
        result.append(FeedViewPost(post: tp.post, reply: nil, reason: nil))
        return result
    }

    /// Recursively collect the parent chain, returning oldest-first.
    private func collectAncestors(_ node: ThreadViewPost?) -> [FeedViewPost] {
        guard let node, case .post(let tp) = node else { return [] }
        var chain = collectAncestors(tp.parent)
        chain.append(FeedViewPost(post: tp.post, reply: nil, reason: nil))
        return chain
    }

    // MARK: - Reply tree

    /// Top-level entry into the recursive reply walker. Uses
    /// `viewModel.sortedReplies` so the toolbar's reply-sort selection
    /// drives row order without a refetch (#0140). Replies whose URI
    /// appears in the focal post's `threadgate.record.hiddenReplies`
    /// list are partitioned out and rendered below a collapsed
    /// "Hidden replies" divider (#0145).
    @ViewBuilder
    private func replyTree(of node: ThreadViewPost, focalURI: ATURI?) -> some View {
        let hiddenURIs = viewModel.hiddenReplyURIs
        let partitioned = partitionReplies(viewModel.sortedReplies, hidden: hiddenURIs)
        ForEach(Array(partitioned.visible.enumerated()), id: \.offset) { _, reply in
            replyRow(reply, depth: 1, focalURI: focalURI)
        }
        if !partitioned.hidden.isEmpty {
            hiddenRepliesDivider(count: partitioned.hidden.count)
            if showHiddenReplies {
                ForEach(Array(partitioned.hidden.enumerated()), id: \.offset) { _, reply in
                    replyRow(reply, depth: 1, focalURI: focalURI, dimmed: true)
                }
            }
        }
    }

    /// Split the focal post's direct replies into the rows that should
    /// render normally and the rows whose URI appears in the OP's
    /// `hiddenReplies` list. Non-`.post` sentinels are treated as
    /// visible — they render their own tombstone in `PostCard`.
    private func partitionReplies(
        _ replies: [ThreadViewPost],
        hidden: Set<ATURI>
    ) -> (visible: [ThreadViewPost], hidden: [ThreadViewPost]) {
        guard !hidden.isEmpty else { return (replies, []) }
        var visible: [ThreadViewPost] = []
        var hiddenList: [ThreadViewPost] = []
        for reply in replies {
            if case .post(let tp) = reply, hidden.contains(tp.post.uri) {
                hiddenList.append(reply)
            } else {
                visible.append(reply)
            }
        }
        return (visible, hiddenList)
    }

    /// "Hidden replies" divider — small centered tappable label. Mirrors
    /// the visual weight of RN's collapsed-section dividers (centered
    /// secondary text with a chevron) so the "Hidden by author" badge on
    /// the dimmed rows below has a clear group header.
    private func hiddenRepliesDivider(count: Int) -> some View {
        Button {
            showHiddenReplies.toggle()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: showHiddenReplies ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(count == 1 ? "Hidden reply" : "Hidden replies")
                    .font(Typography.bodySmall)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.secondary)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Recursive renderer. `depth` is 1-based — the focal post's direct
    /// replies sit at depth 1. Indentation grows with depth up to
    /// `ThreadTree.maxDepth`, then flattens. Returns `AnyView` to break
    /// the self-referential `some View` recursion.
    /// `dimmed` is set for direct replies the OP has hidden via
    /// threadgate; the row paints at reduced opacity with a "Hidden by
    /// author" badge above it. Nested children inherit the dimming so a
    /// hidden subtree reads as a single muted block.
    private func replyRow(
        _ node: ThreadViewPost,
        depth: Int,
        focalURI: ATURI?,
        dimmed: Bool = false
    ) -> AnyView {
        guard case .post(let tp) = node else {
            return AnyView(EmptyView())
        }
        let post = tp.post
        let item = FeedViewPost(post: post, reply: nil, reason: nil)
        let cappedDepth = min(depth, ThreadTree.maxDepth)
        let nestedReplies = (tp.replies ?? []).filter { reply in
            if case .post = reply { return true }
            return false
        }
        let isAtCap = depth >= ThreadTree.maxDepth
        let isExpanded = viewModel.expandedNodes.contains(post.uri)
        let serverHasMore = post.replyCount > nestedReplies.count

        return AnyView(
            VStack(spacing: 0) {
                if dimmed {
                    hiddenByAuthorBadge(depth: cappedDepth)
                }
                TreeReplyRow(
                    item: item,
                    depth: cappedDepth,
                    actions: actions(for: post, focalURI: focalURI)
                )
                .opacity(dimmed ? 0.55 : 1.0)
                Divider()
                // Render direct children when not at the cap, or the
                // user has expanded this subtree past the cap.
                if !isAtCap || isExpanded {
                    ForEach(Array(nestedReplies.enumerated()), id: \.offset) { _, child in
                        replyRow(child, depth: depth + 1, focalURI: focalURI, dimmed: dimmed)
                    }
                }
                // "Show N more replies" — appears when:
                //   1. We're at the cap and the user hasn't expanded yet, or
                //   2. The server reported more nested replies than were
                //      hydrated in the loaded payload.
                if (isAtCap && !isExpanded && !nestedReplies.isEmpty) {
                    showMoreButton(
                        depth: cappedDepth + 1,
                        count: nestedReplies.count,
                        action: { viewModel.toggleExpanded(post.uri) }
                    )
                } else if serverHasMore {
                    showMoreButton(
                        depth: cappedDepth + 1,
                        count: post.replyCount - nestedReplies.count,
                        action: { selectedReplyURI = post.uri }
                    )
                }
            }
        )
    }

    /// Small "Hidden by author" badge rendered above a reply the OP has
    /// suppressed via threadgate. Aligned to the row's left rail so the
    /// badge sits over the same column as the post body. Mirrors the
    /// copy from RN's `ModerationDetailsDialog` ("The author of this
    /// thread has hidden this reply.") in a one-line condensed form
    /// suited for an inline badge.
    private func hiddenByAuthorBadge(depth: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .semibold))
            Text("Hidden by author")
                .font(Typography.footnote)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.secondary)
        .padding(.vertical, Spacing._2xs)
        .padding(.leading, ThreadTree.indentUnit * CGFloat(depth) + Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showMoreButton(depth: Int, count: Int, action: @escaping () -> Void) -> some View {
        let cappedDepth = min(depth, ThreadTree.maxDepth)
        return Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                Text(count == 1 ? "Show 1 more reply" : "Show \(count) more replies")
                    .font(Typography.bodySmall)
            }
            .foregroundStyle(Color.secondary)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, ThreadTree.indentUnit * CGFloat(cappedDepth) + Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func actions(for post: PostView, focalURI: ATURI?) -> PostCard.Actions {
        var a = PostCard.Actions()
        // Tapping a non-focal row (ancestor or reply) pushes a new ThreadView for that
        // post. The focal post is already on screen, so a tap there is a no-op. Pushing
        // via a self-owned navigationDestination avoids the "same item rebound" pitfall
        // that prevented navigation when the parent's binding was re-set to the
        // currently-displayed URI.
        a.onTap = { tapped in
            if tapped.uri == focalURI {
                return
            }
            selectedReplyURI = tapped.uri
        }
        a.onReply = { p in replyTarget = p }
        a.onAuthorTap = onAuthorTap
        a.isBookmarked = bookmarks?.isBookmarked(uri: post.uri.rawValue) ?? false
        a.onBookmark = { p in bookmarks?.toggle(post: p) }
        return a
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tree reply row

/// One reply row inside the recursive tree. Lays out the parent-chain
/// connector lines on the left, then renders a `PostCard` for the post
/// itself. Mirrors the visual structure of RN's
/// `ThreadItemTreePostOuterWrapper` + `ThreadItemTreePostInnerWrapper`
/// from `Bluesky-ReactNative/src/screens/PostThread/components/ThreadItemTreePost.tsx`.
private struct TreeReplyRow: View {

    let item: FeedViewPost
    /// 1-based depth (depth=1 is a direct reply to the focal post).
    /// Capped at `ThreadTree.maxDepth` by the caller.
    let depth: Int
    let actions: PostCard.Actions

    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Ancestor rails: one vertical line per ancestor depth.
            // RN renders `indent - 1` rails (the row's own depth uses
            // a curved corner connector below).
            ForEach(0..<max(0, depth - 1), id: \.self) { _ in
                ZStack(alignment: .trailing) {
                    Color.clear
                        .frame(width: ThreadTree.indentUnit)
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(width: ThreadTree.lineWidth)
                }
            }
            // Row content with a curved connector hooking it onto its
            // parent's rail. The connector is an overlay so the post
            // card's own padding/background is unaffected.
            PostCard(item: item, actions: actions)
                .overlay(alignment: .topLeading) {
                    if depth > 0 {
                        connectorCorner
                    }
                }
        }
        .background(theme.colors.background)
        // UI-test coupling surface (#0177): identifies one reply cell in the
        // tree so the thread suite can count replies below the focal post and
        // tap the first one to push a deeper thread. `children: .contain`
        // keeps the nested PostCard buttons individually addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-reply-cell")
    }

    /// Curved bottom-left corner that joins the row to the rail to its
    /// left. RN renders this with `borderLeftWidth + borderBottomWidth +
    /// borderBottomLeftRadius`; we approximate with a `Path` so we don't
    /// depend on platform-specific border drawing.
    private var connectorCorner: some View {
        ConnectorCornerShape()
            .stroke(theme.colors.border, lineWidth: ThreadTree.lineWidth)
            .frame(width: ThreadTree.indentUnit / 2, height: ThreadTree.treeAvatarSize)
            .offset(x: -ThreadTree.indentUnit / 2, y: 0)
    }
}

/// L-shaped corner: starts at top-left, drops down, curves into a
/// horizontal stub. Approximates RN's `border*Width + border*Radius`
/// rendering of the parent→reply connector.
private struct ConnectorCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius: CGFloat = 6
        // Vertical stem from top-left down to (almost) the bottom.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        // Quarter-arc into the horizontal stub.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

// MARK: - Previews

#Preview("ThreadView — Light") {
    NavigationStack {
        ThreadView(
            uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("ThreadView — Dark") {
    NavigationStack {
        ThreadView(
            uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
