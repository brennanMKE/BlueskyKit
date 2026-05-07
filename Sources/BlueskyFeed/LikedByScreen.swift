import SwiftUI
import Observation
import BlueskyCore
import BlueskyKit
import BlueskyUI
import os

/// Paginated list of profiles that liked a given post — destination of the
/// "X likes" tap target on a focal post (#0139). Mirrors RN's
/// `PostLikedByScreen` (`Bluesky-ReactNative/src/screens/Post/PostLikedBy.tsx`)
/// which renders an infinite-scroll list backed by `app.bsky.feed.getLikes`.
public struct LikedByScreen: View {

    private let postURI: ATURI
    private let network: any NetworkClient
    private let onAuthorTap: ((ProfileView) -> Void)?

    @State private var viewModel: LikedByViewModel

    public init(
        postURI: ATURI,
        network: any NetworkClient,
        onAuthorTap: ((ProfileView) -> Void)? = nil
    ) {
        self.postURI = postURI
        self.network = network
        self.onAuthorTap = onAuthorTap
        _viewModel = State(wrappedValue: LikedByViewModel(network: network, postURI: postURI))
    }

    public var body: some View {
        List {
            if viewModel.likes.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "No Likes Yet",
                    systemImage: "heart",
                    description: Text("When people like this post, they'll show up here.")
                )
            } else {
                ForEach(viewModel.likes, id: \.actor.did) { like in
                    LikedByRow(profile: like.actor) {
                        onAuthorTap?(like.actor)
                    }
                    .onAppear {
                        if like.actor.did == viewModel.likes.last?.actor.did {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Liked By")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await viewModel.load() }
        .task { await viewModel.loadIfNeeded() }
        .overlay {
            if viewModel.isLoading && viewModel.likes.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - LikedByRow

private struct LikedByRow: View {
    let profile: ProfileView
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(url: profile.avatar, handle: profile.handle.rawValue, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let name = profile.displayName, !name.isEmpty {
                            Text(name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else {
                            Text("@\(profile.handle.rawValue)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        if profile.verification?.isVerified == true {
                            VerifiedBadge()
                        }
                    }
                    if profile.displayName?.isEmpty == false {
                        Text("@\(profile.handle.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let bio = profile.description, !bio.isEmpty {
                        Text(bio)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LikedByViewModel

@Observable @MainActor
public final class LikedByViewModel {
    public private(set) var likes: [LikeActor] = []
    public private(set) var cursor: Cursor?
    public private(set) var hasMore: Bool = true
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let network: any NetworkClient
    private let postURI: ATURI
    private let pageSize = 30
    private let logger = Logger(subsystem: "app.bsky", category: "LikedByViewModel")

    public init(network: any NetworkClient, postURI: ATURI) {
        self.network = network
        self.postURI = postURI
    }

    /// Load the first page only when the view appears for the first time.
    /// Pull-to-refresh goes through `load()` directly.
    public func loadIfNeeded() async {
        guard likes.isEmpty, !isLoading else { return }
        await load()
    }

    /// Reload from page zero. Replaces `likes` on success and resets the cursor.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp: GetLikesResponse = try await network.get(
                lexicon: "app.bsky.feed.getLikes",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize)
                ]
            )
            likes = resp.likes
            cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getLikes load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Append the next page if more exist.
    public func loadMore() async {
        guard hasMore, !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetLikesResponse = try await network.get(
                lexicon: "app.bsky.feed.getLikes",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize),
                    "cursor": cursor
                ]
            )
            likes.append(contentsOf: resp.likes)
            self.cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getLikes loadMore failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - Previews

#Preview("LikedByScreen — Light") {
    NavigationStack {
        LikedByScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("LikedByScreen — Dark") {
    NavigationStack {
        LikedByScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
