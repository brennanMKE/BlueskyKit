import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "FollowingFeedPreferences"
)

// MARK: - FollowingFeedPreferencesScreen

/// Settings → Content & Media → Following feed preferences.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Settings/FollowingFeedPreferences.tsx`.
/// State persists via `app.bsky.actor.defs#feedViewPref` (keyed by
/// `feed: "home"`) inside `app.bsky.actor.putPreferences`.
///
/// Three server-backed toggles match the RN screen:
/// 1. **Show replies** — inverse of `hideReplies`.
/// 2. **Show reposts** — inverse of `hideReposts`.
/// 3. **Show quote posts** — inverse of `hideQuotePosts`.
///
/// RN's screen also exposes a `lab_mergeFeedEnabled` experimental toggle. That
/// labs flag is not modeled in `FeedViewPref` (matches the precedent set by
/// `lab_treeViewEnabled` in `ThreadPreferencesScreen`) and is deferred.
///
/// `hideRepliesByUnfollowed` and `hideRepliesByLikeCount` round-trip on the
/// value type but are commented as **"Legacy, ignored"** in RN's
/// `DEFAULT_HOME_FEED_PREFS`; the RN screen does not surface them and neither
/// does this one.
///
/// Cross-cuts with #0017 (in-feed filter chips on the Following timeline):
/// that work landed as per-tab transient state. Once these prefs are consumed
/// by `FeedViewModel`, the in-feed UI can read from / write to the server-
/// backed source instead. See Gotchas in #0117.
public struct FollowingFeedPreferencesScreen: View {

    private let network: any NetworkClient
    @State private var model: FollowingFeedPreferencesViewModel

    public init(network: any NetworkClient) {
        self.network = network
        _model = State(initialValue: FollowingFeedPreferencesViewModel(network: network))
    }

    public var body: some View {
        Form {
            Section {
                Text("These settings only apply to the Following feed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Show replies",
                    isOn: Binding(
                        get: { !model.hideReplies },
                        set: { newValue in
                            Task { await model.setHideReplies(!newValue) }
                        }
                    )
                )
                Toggle(
                    "Show reposts",
                    isOn: Binding(
                        get: { !model.hideReposts },
                        set: { newValue in
                            Task { await model.setHideReposts(!newValue) }
                        }
                    )
                )
                Toggle(
                    "Show quote posts",
                    isOn: Binding(
                        get: { !model.hideQuotePosts },
                        set: { newValue in
                            Task { await model.setHideQuotePosts(!newValue) }
                        }
                    )
                )
            } header: {
                Text("Show in Following")
            }
        }
        .navigationTitle("Following Feed Preferences")
        .task { await model.load() }
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            },
            message: {
                if let msg = model.errorMessage { Text(msg) }
            }
        )
    }
}

// MARK: - View model

@MainActor
@Observable
final class FollowingFeedPreferencesViewModel {

    /// Default `false` so toggles render as "Show replies = on" before
    /// `getPreferences` returns — matches RN's `DEFAULT_HOME_FEED_PREFS`.
    var hideReplies: Bool = FeedViewPref.defaultHome.hideReplies
    var hideReposts: Bool = FeedViewPref.defaultHome.hideReposts
    var hideQuotePosts: Bool = FeedViewPref.defaultHome.hideQuotePosts

    /// Round-tripped from the server but not exposed by the screen — RN
    /// flags both as legacy/ignored. We preserve the existing values when
    /// writing back to avoid clobbering whatever the server holds.
    private var hideRepliesByUnfollowed: Bool = FeedViewPref.defaultHome.hideRepliesByUnfollowed
    private var hideRepliesByLikeCount: Int = FeedViewPref.defaultHome.hideRepliesByLikeCount

    var isLoading = false
    var errorMessage: String?

    private let network: any NetworkClient

    init(network: any NetworkClient) {
        self.network = network
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            if let pref = resp.homeFeedView {
                self.hideReplies = pref.hideReplies
                self.hideReposts = pref.hideReposts
                self.hideQuotePosts = pref.hideQuotePosts
                self.hideRepliesByUnfollowed = pref.hideRepliesByUnfollowed
                self.hideRepliesByLikeCount = pref.hideRepliesByLikeCount
            }
        } catch {
            logger.debug("getPreferences refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Optimistic update: flip the local flag, write to the server, and roll
    /// back on failure. RN's `useSetFeedViewPreferencesMutation` invalidates
    /// the prefs query on success; we just keep the local state authoritative
    /// until `load()` runs again.
    func setHideReplies(_ newValue: Bool) async {
        guard newValue != hideReplies else { return }
        let previous = hideReplies
        hideReplies = newValue
        await write(rollback: { [weak self] in self?.hideReplies = previous })
    }

    func setHideReposts(_ newValue: Bool) async {
        guard newValue != hideReposts else { return }
        let previous = hideReposts
        hideReposts = newValue
        await write(rollback: { [weak self] in self?.hideReposts = previous })
    }

    func setHideQuotePosts(_ newValue: Bool) async {
        guard newValue != hideQuotePosts else { return }
        let previous = hideQuotePosts
        hideQuotePosts = newValue
        await write(rollback: { [weak self] in self?.hideQuotePosts = previous })
    }

    private func write(rollback: @escaping @MainActor () -> Void) async {
        let pref = FeedViewPref(
            feed: "home",
            hideReplies: hideReplies,
            hideRepliesByUnfollowed: hideRepliesByUnfollowed,
            hideRepliesByLikeCount: hideRepliesByLikeCount,
            hideReposts: hideReposts,
            hideQuotePosts: hideQuotePosts
        )
        do {
            // Read-modify-write (#0201): merge into the full preferences
            // array; the feedView mutation is keyed by `feed`, so other
            // feeds' entries also survive.
            try await PreferencesWriter.shared.update(network: network, .feedView(pref))
        } catch {
            logger.error("putPreferences(feedView) failed: \(error.localizedDescription, privacy: .public)")
            rollback()
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

#Preview("FollowingFeedPreferencesScreen — Light") {
    NavigationStack {
        FollowingFeedPreferencesScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("FollowingFeedPreferencesScreen — Dark") {
    NavigationStack {
        FollowingFeedPreferencesScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
