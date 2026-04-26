import AVKit
import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Full-screen vertical-scroll video feed backed by a video algorithm feed generator.
public struct VideoFeedView: View {
    @State private var viewModel: FeedViewModel
    @State private var currentIndex = 0

    public init(network: any NetworkClient, accountStore: any AccountStore, feedURI: String) {
        _viewModel = State(
            initialValue: FeedViewModel(
                network: network,
                accountStore: accountStore,
                selection: .feed(uri: feedURI)
            )
        )
    }

    private var videoPosts: [FeedViewPost] {
        viewModel.posts.filter { post in
            if case .video = post.post.embed { return true }
            return false
        }
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && videoPosts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if videoPosts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Videos",
                    systemImage: "video.slash",
                    description: Text("No video posts found in this feed.")
                )
            } else {
                videoScrollView
            }
        }
        .task { await viewModel.loadInitial() }
        .navigationTitle("Video")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var videoScrollView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(videoPosts.enumerated()), id: \.element.post.uri) { index, feedPost in
                if case .video(let video) = feedPost.post.embed {
                    VideoPostPage(feedPost: feedPost, video: video)
                        .tag(index)
                        .onAppear {
                            if index >= videoPosts.count - 2 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        #endif
    }
}

private struct VideoPostPage: View {
    let feedPost: FeedViewPost
    let video: EmbedVideoView

    @State private var player: AVPlayer?
    @State private var isShowingInfo = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AvatarView(
                        url: feedPost.post.author.avatar,
                        handle: feedPost.post.author.handle.rawValue,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = feedPost.post.author.displayName {
                            Text(name).fontWeight(.semibold).foregroundStyle(.white)
                        }
                        Text("@\(feedPost.post.author.handle.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                if !feedPost.post.record.text.isEmpty {
                    let text = feedPost.post.record.text
                    Text(text)
                        .foregroundStyle(.white)
                        .lineLimit(isShowingInfo ? nil : 2)
                        .onTapGesture { isShowingInfo.toggle() }
                }

                if let alt = video.alt, !alt.isEmpty, isShowingInfo {
                    Text("Alt: \(alt)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding()
            .background(.black.opacity(0.4))
        }
        .onAppear {
            let p = AVPlayer(url: video.playlist)
            p.play()
            self.player = p
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
