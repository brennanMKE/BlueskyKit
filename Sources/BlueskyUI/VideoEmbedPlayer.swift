import AVKit
import SwiftUI
import BlueskyCore

// MARK: - Autoplay environment

/// Whether `VideoEmbedPlayer` should auto-play the inline video when the cell
/// becomes visible. Mirrors RN's `useAutoplayDisabled()` (inverted) — RN reads
/// the user's "autoplay videos" preference and gates `autoplay` on the native
/// `BlueskyVideoView`. The Settings module owns the persisted value
/// (`SettingsViewModel.autoplayVideo`); the host app threads it down through
/// the environment so the embed renderer in BlueskyUI doesn't have to depend
/// on BlueskySettings.
extension EnvironmentValues {
    @Entry public var blueskyAutoplayVideos: Bool = true
}

public extension View {
    /// Inject the user's "autoplay videos" preference for inline video embeds.
    /// Defaults to `true` to match RN's default behaviour when no preference
    /// is set.
    func blueskyAutoplayVideos(_ enabled: Bool) -> some View {
        environment(\.blueskyAutoplayVideos, enabled)
    }
}

// MARK: - VideoEmbedPlayer

/// Inline video player for `EmbedVideoView` embeds in feed and thread cells.
///
/// Mirrors RN's `VideoEmbedInnerNative.tsx`:
/// - Auto-plays muted when the cell is on-screen (gated on `autoplayVideos`).
/// - Loops via `AVPlayerItemDidPlayToEndTime` (RN sets `expo-video.loop`).
/// - Mute toggle pinned top-trailing.
/// - Tap opens a fullscreen sheet with native AVKit controls (scrubber,
///   time, AirPlay, picture-in-picture).
///
/// Each cell owns its own `AVPlayer` lazily created in `onAppear` and torn
/// down in `onDisappear` so the feed doesn't accumulate player instances as
/// the user scrolls.
public struct VideoEmbedPlayer: View {

    let video: EmbedVideoView

    @Environment(\.blueskyAutoplayVideos) private var autoplayVideos
    @Environment(\.blueskyTheme) private var theme

    @State private var player: AVPlayer?
    @State private var isMuted = true
    @State private var isFullscreen = false
    /// Token returned by `addPeriodicTimeObserver`; we don't currently use a
    /// scrubber inline (the fullscreen sheet has the native one), but we keep
    /// the slot so the lifecycle pattern matches `VideoFeedView`.
    @State private var didPlayToEndObserver: NSObjectProtocol?

    public init(video: EmbedVideoView) {
        self.video = video
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            inlineSurface
            if player != nil {
                muteToggle
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxHeight: 280)
        .contentShape(Rectangle())
        .onTapGesture { isFullscreen = true }
        .onAppear { setUpPlayerIfNeeded() }
        .onDisappear { tearDownPlayer() }
        #if os(iOS)
        .fullScreenCover(isPresented: $isFullscreen) {
            FullscreenVideoSheet(video: video)
        }
        #else
        .sheet(isPresented: $isFullscreen) {
            FullscreenVideoSheet(video: video)
        }
        #endif
    }

    // MARK: Inline surface

    @ViewBuilder
    private var inlineSurface: some View {
        if autoplayVideos, let player {
            // Inline auto-play branch — mirrors RN's `VideoEmbedInnerNative`.
            // `disabled(true)` suppresses the system playback controls so the
            // tap gesture above can win and open the fullscreen sheet.
            VideoPlayer(player: player)
                .disabled(true)
                .aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            // Static-thumbnail branch — autoplay off. Matches the previous
            // behaviour where tapping opens the fullscreen player.
            thumbnailWithPlayBadge
        }
    }

    private var thumbnailWithPlayBadge: some View {
        ZStack {
            if let thumb = video.thumbnail {
                AsyncImage(url: thumb) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.black.opacity(0.1)
                    }
                }
            } else {
                Color.black.opacity(0.1)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private var muteToggle: some View {
        Button {
            isMuted.toggle()
            player?.isMuted = isMuted
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
    }

    private var aspectRatio: CGFloat? {
        guard let dims = video.aspectRatio else { return nil }
        let ratio = CGFloat(dims.width) / CGFloat(dims.height)
        // Cap tall videos at 1:2 to avoid eating the entire feed cell —
        // mirrors RN's `Math.max(aspectRatio, 1/2)` in `VideoEmbed/index.tsx`.
        return max(ratio, 0.5)
    }

    // MARK: Player lifecycle

    private func setUpPlayerIfNeeded() {
        // Only spin up an AVPlayer when autoplay is enabled. When disabled the
        // user opens the fullscreen sheet on tap and that sheet creates its
        // own player.
        guard autoplayVideos, player == nil else { return }
        let p = AVPlayer(url: video.playlist)
        p.isMuted = isMuted
        p.play()
        // Loop on item end — same trick as `VideoFeedView`.
        if let item = p.currentItem {
            didPlayToEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
        }
        player = p
    }

    private func tearDownPlayer() {
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        player?.pause()
        player = nil
    }
}

// MARK: - Fullscreen sheet

/// Fullscreen video player presented from a feed/thread embed tap. Uses
/// `VideoPlayer` *with* system controls (scrubber, time, mute, AirPlay,
/// picture-in-picture). Each presentation creates a fresh `AVPlayer` so
/// dismissing the sheet tears playback down cleanly.
private struct FullscreenVideoSheet: View {
    let video: EmbedVideoView
    @State private var player: AVPlayer?
    @State private var didPlayToEndObserver: NSObjectProtocol?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding()
        }
        .onAppear {
            let p = AVPlayer(url: video.playlist)
            p.isMuted = false
            p.play()
            if let item = p.currentItem {
                didPlayToEndObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak p] _ in
                    p?.seek(to: .zero)
                    p?.play()
                }
            }
            player = p
        }
        .onDisappear {
            if let observer = didPlayToEndObserver {
                NotificationCenter.default.removeObserver(observer)
                didPlayToEndObserver = nil
            }
            player?.pause()
            player = nil
        }
    }
}
