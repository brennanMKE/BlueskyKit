import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "ThreadPreferences"
)

// MARK: - ThreadPreferencesScreen

/// Settings → Content & Media → Thread preferences.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Settings/ThreadPreferences.tsx`.
/// State persists via `app.bsky.actor.defs#threadViewPref` inside
/// `app.bsky.actor.putPreferences`.
///
/// Two server-backed sections:
/// 1. **Sort replies** — radio: Hot · Top · Newest · Oldest · Random.
///    Maps to `sort` ∈ `{"hotness", "most-likes", "newest", "oldest",
///    "random"}`.
/// 2. **Other** — *Prioritize people you follow* toggle. Maps to
///    `prioritizeFollowedUsers`.
///
/// Tree-view, "Hide replies by muted accounts", and "Hide replies by people
/// you don't follow" rows from the live RN screen are deferred — they ride in
/// other lexicon prefs (`lab_treeViewEnabled`, etc.) we have not modeled. See
/// the issue #0116 follow-up note in Gotchas.
///
/// Cross-cuts with #0140 (reply-sort dropdown in `ThreadView`): the screen
/// writes `sort`, and `GetPreferencesResponse.threadView` exposes it so
/// `ThreadView` can pick up the user's choice once that issue lands.
public struct ThreadPreferencesScreen: View {

    private let network: any NetworkClient
    @State private var model: ThreadPreferencesViewModel

    public init(network: any NetworkClient) {
        self.network = network
        _model = State(initialValue: ThreadPreferencesViewModel(network: network))
    }

    public var body: some View {
        Form {
            Section {
                ForEach(SortOption.allCases) { option in
                    Button {
                        Task { await model.setSort(option.lexiconValue) }
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.sort == option.lexiconValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(model.sort == option.lexiconValue ? [.isSelected] : [])
                }
            } header: {
                Text("Sort replies")
            } footer: {
                Text("Sort replies to the same post by:")
            }

            Section {
                Toggle(
                    "Prioritize people you follow",
                    isOn: Binding(
                        get: { model.prioritizeFollowedUsers },
                        set: { newValue in
                            Task { await model.setPrioritizeFollowedUsers(newValue) }
                        }
                    )
                )
            } header: {
                Text("Other")
            }
        }
        .navigationTitle("Thread Preferences")
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

// MARK: - Sort option

/// Order matches RN's `ThreadPreferences.tsx` Toggle.Group order, with the
/// extended set of values supported by `app.bsky.actor.defs#threadViewPref`.
/// RN's current screen exposes only Top/Oldest/Newest, but the lexicon also
/// admits `hotness` and `random`; the issue spec calls for all five so we
/// surface all five.
private enum SortOption: String, CaseIterable, Identifiable {
    case hot
    case top
    case newest
    case oldest
    case random

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hot: return "Hot"
        case .top: return "Top"
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .random: return "Random"
        }
    }

    var lexiconValue: String {
        switch self {
        case .hot: return "hotness"
        case .top: return "most-likes"
        case .newest: return "newest"
        case .oldest: return "oldest"
        case .random: return "random"
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class ThreadPreferencesViewModel {

    /// Lexicon string for the active sort. Initialized to the documented
    /// default (`"hotness"`) so the radio group shows a checked row before
    /// `getPreferences` returns.
    var sort: String = ThreadViewPref.defaultPref.sort

    /// Whether replies from accounts the user follows are surfaced first.
    /// Defaults `true` to match the RN appview behavior when the user has
    /// never written a `threadViewPref`.
    var prioritizeFollowedUsers: Bool = ThreadViewPref.defaultPref.prioritizeFollowedUsers

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
            if let pref = resp.threadView {
                self.sort = pref.sort
                self.prioritizeFollowedUsers = pref.prioritizeFollowedUsers
            }
        } catch {
            logger.debug("getPreferences refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes a `threadViewPref` carrying the new `sort` value while keeping
    /// the existing `prioritizeFollowedUsers` flag. Optimistic update with
    /// rollback on failure.
    func setSort(_ newValue: String) async {
        guard newValue != sort else { return }
        let previous = sort
        sort = newValue
        await write(rollback: { [weak self] in self?.sort = previous })
    }

    /// Writes a `threadViewPref` carrying the new `prioritizeFollowedUsers`
    /// flag while keeping the existing `sort`. Optimistic update with
    /// rollback on failure.
    func setPrioritizeFollowedUsers(_ newValue: Bool) async {
        guard newValue != prioritizeFollowedUsers else { return }
        let previous = prioritizeFollowedUsers
        prioritizeFollowedUsers = newValue
        await write(rollback: { [weak self] in self?.prioritizeFollowedUsers = previous })
    }

    private func write(rollback: @escaping @MainActor () -> Void) async {
        let pref = ThreadViewPref(sort: sort, prioritizeFollowedUsers: prioritizeFollowedUsers)
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .threadView(pref))
        } catch {
            logger.error("putPreferences(threadView) failed: \(error.localizedDescription, privacy: .public)")
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

#Preview("ThreadPreferencesScreen — Light") {
    NavigationStack {
        ThreadPreferencesScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("ThreadPreferencesScreen — Dark") {
    NavigationStack {
        ThreadPreferencesScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
