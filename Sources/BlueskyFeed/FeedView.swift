import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// The home feed view — feed switcher at top, infinite-scroll post list below.
public struct FeedView: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    var onPostTap: ((PostView) -> Void)?
    var onAuthorTap: ((ProfileBasic) -> Void)?

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
    }

    @State private var selection: FeedSelection = .timeline
    @State private var viewModels: [FeedSelection: FeedViewModel] = [:]

    private var currentViewModel: FeedViewModel {
        if let existing = viewModels[selection] { return existing }
        let vm = FeedViewModel(network: network, accountStore: accountStore, selection: selection)
        viewModels[selection] = vm
        return vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            FeedSwitcherView(selection: $selection)
            Divider()
            feedList
        }
        .navigationTitle("Home")
    }

    private var feedList: some View {
        let vm = currentViewModel
        return Group {
            if vm.posts.isEmpty && vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.posts.isEmpty, let msg = vm.errorMessage {
                errorView(msg, vm: vm)
            } else {
                list(vm: vm)
            }
        }
        .task(id: selection) {
            await vm.loadInitial()
        }
    }

    private func list(vm: FeedViewModel) -> some View {
        List {
            ForEach(vm.posts, id: \.post.uri) { item in
                PostCard(item: item, actions: actions(for: item, vm: vm))
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if item.post.uri == vm.posts.last?.post.uri {
                            Task { await vm.loadMore() }
                        }
                    }
            }
            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.refresh() }
    }

    private func errorView(_ message: String, vm: FeedViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actions(for item: FeedViewPost, vm: FeedViewModel) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = onPostTap
        a.onAuthorTap = onAuthorTap
        a.onLike = { post in
            Task {
                if post.viewer?.like != nil {
                    await vm.unlike(post: post)
                } else {
                    await vm.like(post: post)
                }
            }
        }
        a.onRepost = { post in
            Task {
                if post.viewer?.repost != nil {
                    await vm.unrepost(post: post)
                } else {
                    await vm.repost(post: post)
                }
            }
        }
        return a
    }
}
