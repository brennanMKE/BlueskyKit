import SwiftUI
import BlueskyCore

// OfflineBanner is in BlueskyUI, which depends only on BlueskyCore.
// BlueskyCore defines NetworkPathStatus; NetworkPathMonitoring lives in BlueskyKit.
// To avoid pulling BlueskyKit into BlueskyUI's dependency graph, the banner
// reads from a simple @Observable state object updated by the host view.

/// Drives `OfflineBanner`'s visible state. Owned by `MainTabView` (or another
/// `@MainActor` host), updated by listening to `env.pathMonitor.statusStream`.
@Observable
public final class OfflineBannerState {
    public var isOffline: Bool = false
    public init() {}
}

/// A pill-shaped banner displayed at the top of the content area when the device
/// has no viable network path.
public struct OfflineBanner: View {
    private let state: OfflineBannerState

    public init(state: OfflineBannerState) {
        self.state = state
    }

    public var body: some View {
        if state.isOffline {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "wifi.slash")
                    .imageScale(.small)
                Text("You're offline")
                    .font(.system(size: Typography.sm, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Color(.sRGB, red: 0.40, green: 0.40, blue: 0.40, opacity: 0.92))
            .clipShape(Capsule())
            .padding(.top, Spacing.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
