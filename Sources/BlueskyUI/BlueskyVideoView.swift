import AVKit
import SwiftUI

/// A video playback surface backed directly by AVKit's platform views —
/// `AVPlayerView` on macOS, `AVPlayerViewController` on iOS — instead of
/// SwiftUI's `VideoPlayer`.
///
/// `VideoPlayer` lives in the `_AVKit_SwiftUI` cross-import overlay, and
/// instantiating its generic class metadata during the initial view-graph
/// build races AttributeGraph's background `TypeDescriptorCache` thread,
/// intermittently aborting the app at launch (#0195,
/// `getSuperclassMetadata` fatal error). Wrapping the platform views in our
/// own non-generic representable keeps the overlay's generics out of the
/// process entirely.
///
/// Named after RN's native `BlueskyVideoView`, which plays the same role:
/// a plain platform player surface the JS/SwiftUI layer composes overlays on.
///
/// When `showsControls` is `false` the surface is purely presentational —
/// it does not hit-test, so taps fall through to the caller's own gesture
/// overlays (fullscreen-on-tap in `VideoEmbedPlayer`, tap-to-pause in
/// `VideoFeedView`).
public struct BlueskyVideoView: View {

    private let player: AVPlayer
    private let showsControls: Bool

    public init(player: AVPlayer, showsControls: Bool = false) {
        self.player = player
        self.showsControls = showsControls
    }

    public var body: some View {
        PlayerSurface(player: player, showsControls: showsControls)
            .allowsHitTesting(showsControls)
    }
}

#if os(macOS)

private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let showsControls: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .inline : .none
        view.showsFullScreenToggleButton = showsControls
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.controlsStyle = showsControls ? .inline : .none
        view.showsFullScreenToggleButton = showsControls
        if view.player !== player {
            view.player = player
        }
    }
}

#else

private struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = showsControls
        controller.allowsPictureInPicturePlayback = showsControls
        controller.videoGravity = .resizeAspect
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.showsPlaybackControls = showsControls
        controller.allowsPictureInPicturePlayback = showsControls
        if controller.player !== player {
            controller.player = player
        }
    }
}

#endif
