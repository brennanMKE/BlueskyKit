import SwiftUI
import Observation
import BlueskyCore
import BlueskyKit
import BlueskyUI
import os

/// Paginated list of profiles that reposted a given post — destination of the
/// "X reposts" tap target on a focal post (#0139). Mirrors RN's
/// `PostRepostedByScreen` (`Bluesky-ReactNative/src/screens/Post/PostRepostedBy.tsx`)
/// which pages over `app.bsky.feed.getRepostedBy`.
public struct RepostedByScreen: View {

    private let postURI: ATURI
    private let network: any NetworkClient
    private let onAuthorTap: ((ProfileView) -> Void)?

    @State private var viewModel: RepostedByViewModel

    public init(
        postURI: ATURI,
        network: any NetworkClient,
        onAuthorTap: ((ProfileView) -> Void)? = nil
    ) {
        self.postURI = postURI
        self.network = network
        self.onAuthorTap = onAuthorTap
        _viewModel = State(wrappedValue: RepostedByViewModel(network: network, postURI: postURI))
    }

    public var body: some View {
        List {
            if viewModel.repostedBy.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "No Reposts Yet",
                    systemImage: "arrow.2.squarepath",
                    description: Text("When people repost this, they'll show up here.")
                )
            } else {
                ForEach(viewModel.repostedBy, id: \.did) { profile in
                    RepostedByRow(profile: profile) {
                        onAuthorTap?(profile)
                    }
                    .onAppear {
                        if profile.did == viewModel.repostedBy.last?.did {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reposted By")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await viewModel.load() }
        .task { await viewModel.loadIfNeeded() }
        .overlay {
            if viewModel.isLoading && viewModel.repostedBy.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - RepostedByRow

private struct RepostedByRow: View {
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

// MARK: - RepostedByViewModel

@Observable @MainActor
public final class RepostedByViewModel {
    public private(set) var repostedBy: [ProfileView] = []
    public private(set) var cursor: Cursor?
    public private(set) var hasMore: Bool = true
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let network: any NetworkClient
    private let postURI: ATURI
    private let pageSize = 30
    private let logger = Logger(subsystem: "app.bsky", category: "RepostedByViewModel")

    public init(network: any NetworkClient, postURI: ATURI) {
        self.network = network
        self.postURI = postURI
    }

    public func loadIfNeeded() async {
        guard repostedBy.isEmpty, !isLoading else { return }
        await load()
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp: GetRepostedByResponse = try await network.get(
                lexicon: "app.bsky.feed.getRepostedBy",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize)
                ]
            )
            repostedBy = resp.repostedBy
            cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getRepostedBy load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetRepostedByResponse = try await network.get(
                lexicon: "app.bsky.feed.getRepostedBy",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize),
                    "cursor": cursor
                ]
            )
            repostedBy.append(contentsOf: resp.repostedBy)
            self.cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getRepostedBy loadMore failed: \(error.localizedDescription, privacy: .public)")
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

#Preview("RepostedByScreen — Light") {
    NavigationStack {
        RepostedByScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("RepostedByScreen — Dark") {
    NavigationStack {
        RepostedByScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
