import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "PostInteractionSettings"
)

// MARK: - PostInteractionSettingsScreen

/// Post Interaction Settings — defaults for who can reply to and quote the
/// user's new posts.
///
/// Mirrors `Bluesky-ReactNative/src/screens/ModerationInteractionSettings/
/// index.tsx`, which renders a tip admonition followed by RN's
/// `PostInteractionSettingsForm`. State persists via
/// `app.bsky.actor.defs#postInteractionSettingsPref` inside
/// `app.bsky.actor.putPreferences`. Composer (#0098) reads the same pref to
/// seed initial values for new posts.
///
/// Two server-backed sections:
///
/// 1. **Allow replies from** — top-level radio: Anyone / Nobody (mirrors RN's
///    first toggle group). When neither "Anyone" nor "Nobody" is selected, the
///    form falls into a **Combined** mode where the user can independently
///    enable Followers / People you follow / People you mention. RN combines
///    these as a union (any matching rule grants permission).
///
///    The "Specific lists" branch in RN requires a list picker; we surface a
///    summary read-only row when the loaded pref already contains list rules,
///    but creating new list rules in this client is deferred to RN parity for
///    a follow-up. The radio still preserves any list rules round-trip.
///
/// 2. **Allow quote posts** — toggle. Maps to whether `postgateEmbeddingRules`
///    contains `app.bsky.feed.postgate#disableRule`. RN renders this as a
///    single switch.
///
/// **DM allowance** is *not* part of this screen. Per the issue spec, DMs
/// ride on `chat.bsky.actor.declaration` (a separate record on the actor's
/// `chat.bsky.actor.declaration` collection, not the `actor.defs` prefs
/// blob). It's tracked separately and intentionally deferred from this
/// screen — no row, no placeholder.
public struct PostInteractionSettingsScreen: View {

    private let network: any NetworkClient
    @State private var model: PostInteractionSettingsViewModel

    public init(network: any NetworkClient) {
        self.network = network
        _model = State(initialValue: PostInteractionSettingsViewModel(network: network))
    }

    public var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                    Text(
                        "These settings will be used as your defaults when creating new posts. You can edit these for a specific post from the composer."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            allowRepliesSection
            allowQuotesSection
        }
        .navigationTitle("Post Interaction Settings")
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

    // MARK: - Replies section

    @ViewBuilder
    private var allowRepliesSection: some View {
        Section {
            ForEach(ReplyMode.allCases) { mode in
                Button {
                    Task { await model.setReplyMode(mode) }
                } label: {
                    HStack {
                        Text(mode.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if model.replyMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(model.replyMode == mode ? [.isSelected] : [])
            }

            if model.replyMode == .combined {
                Toggle("Your followers", isOn: Binding(
                    get: { model.combinedFollowers },
                    set: { newValue in
                        Task { await model.setCombinedFollowers(newValue) }
                    }
                ))
                Toggle("People you follow", isOn: Binding(
                    get: { model.combinedFollowing },
                    set: { newValue in
                        Task { await model.setCombinedFollowing(newValue) }
                    }
                ))
                Toggle("People you mention", isOn: Binding(
                    get: { model.combinedMention },
                    set: { newValue in
                        Task { await model.setCombinedMention(newValue) }
                    }
                ))

                if !model.preservedListRules.isEmpty {
                    HStack {
                        Label(
                            "\(model.preservedListRules.count) list\(model.preservedListRules.count == 1 ? "" : "s") allowed",
                            systemImage: "person.3"
                        )
                        Spacer()
                        Text("Edit on bsky.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Allow replies from")
        } footer: {
            Text(replyFooter)
        }
    }

    private var replyFooter: String {
        switch model.replyMode {
        case .anyone:
            return "Anyone on Bluesky can reply to your new posts."
        case .nobody:
            return "Replies will be disabled by default. You can change this per-post in the composer."
        case .combined:
            let parts: [String] = [
                model.combinedFollowers ? "your followers" : nil,
                model.combinedFollowing ? "people you follow" : nil,
                model.combinedMention ? "people you mention" : nil,
                model.preservedListRules.isEmpty ? nil : "members of \(model.preservedListRules.count) list\(model.preservedListRules.count == 1 ? "" : "s")",
            ].compactMap { $0 }
            if parts.isEmpty {
                return "Choose at least one group below, or pick Anyone or Nobody above."
            }
            return "Only " + parts.joined(separator: ", ") + " can reply by default."
        }
    }

    // MARK: - Quotes section

    @ViewBuilder
    private var allowQuotesSection: some View {
        Section {
            Toggle("Allow quote posts", isOn: Binding(
                get: { model.quotesEnabled },
                set: { newValue in
                    Task { await model.setQuotesEnabled(newValue) }
                }
            ))
        } header: {
            Text("Quote posts")
        } footer: {
            Text(model.quotesEnabled
                 ? "Other accounts can quote your new posts."
                 : "Quote posts will be disabled by default. You can change this per-post in the composer.")
        }
    }
}

// MARK: - Reply mode

/// Top-level radio choices for "Allow replies from". The labels mirror RN's
/// dialog: the first row group offers Anyone / Nobody as a one-of-three radio
/// (the third state being the combined per-rule selector below). RN does not
/// localize these strings beyond the values copied here.
enum ReplyMode: String, CaseIterable, Identifiable {
    case anyone
    case combined
    case nobody

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anyone:   return "Anyone"
        case .combined: return "Combined"
        case .nobody:   return "Nobody"
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class PostInteractionSettingsViewModel {

    var replyMode: ReplyMode = .anyone
    var combinedFollowers: Bool = false
    var combinedFollowing: Bool = false
    var combinedMention: Bool = false

    /// Round-tripped list rules pulled out of the server pref. Read-only here;
    /// editing list rules requires a list picker, which is deferred to a
    /// follow-up. Kept in state so writes preserve the user's existing list
    /// selections instead of dropping them.
    var preservedListRules: [ATURI] = []

    var quotesEnabled: Bool = true

    var isLoading = false
    var errorMessage: String?

    private let network: any NetworkClient

    init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            applyPref(resp.postInteractionSettings ?? .defaultPref)
        } catch {
            logger.debug("getPreferences refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Project the lexicon pref onto the radio + per-rule UI state.
    private func applyPref(_ pref: PostInteractionSettingsPref) {
        // Threadgate: nil → anyone, [] → nobody, otherwise → combined.
        if let rules = pref.threadgateAllowRules {
            if rules.isEmpty {
                replyMode = .nobody
                combinedFollowers = false
                combinedFollowing = false
                combinedMention = false
                preservedListRules = []
            } else {
                replyMode = .combined
                combinedFollowers = rules.contains { if case .follower = $0 { true } else { false } }
                combinedFollowing = rules.contains { if case .following = $0 { true } else { false } }
                combinedMention = rules.contains { if case .mention = $0 { true } else { false } }
                preservedListRules = rules.compactMap {
                    if case .list(let uri) = $0 { uri } else { nil }
                }
            }
        } else {
            replyMode = .anyone
            combinedFollowers = false
            combinedFollowing = false
            combinedMention = false
            preservedListRules = []
        }

        // Postgate: any `#disableRule` present → quotes off.
        let hasDisable = pref.postgateEmbeddingRules.contains {
            if case .disable = $0 { true } else { false }
        }
        quotesEnabled = !hasDisable
    }

    // MARK: Mutations

    func setReplyMode(_ newValue: ReplyMode) async {
        guard newValue != replyMode else { return }
        let snapshot = currentSnapshot
        replyMode = newValue
        // Default the combined toggles to a sensible starting state when the
        // user lands on the combined branch for the first time. RN's UI
        // implicitly defaults to "no boxes checked" → "no one can reply except
        // listed groups", which is bizarre when zero groups are checked.
        // Mirror the RN behavior: leave toggles where the user last set them.
        await write(snapshot: snapshot)
    }

    func setCombinedFollowers(_ newValue: Bool) async {
        let snapshot = currentSnapshot
        combinedFollowers = newValue
        await write(snapshot: snapshot)
    }

    func setCombinedFollowing(_ newValue: Bool) async {
        let snapshot = currentSnapshot
        combinedFollowing = newValue
        await write(snapshot: snapshot)
    }

    func setCombinedMention(_ newValue: Bool) async {
        let snapshot = currentSnapshot
        combinedMention = newValue
        await write(snapshot: snapshot)
    }

    func setQuotesEnabled(_ newValue: Bool) async {
        let snapshot = currentSnapshot
        quotesEnabled = newValue
        await write(snapshot: snapshot)
    }

    // MARK: Snapshot / rollback / write

    private struct Snapshot {
        let replyMode: ReplyMode
        let combinedFollowers: Bool
        let combinedFollowing: Bool
        let combinedMention: Bool
        let preservedListRules: [ATURI]
        let quotesEnabled: Bool
    }

    private var currentSnapshot: Snapshot {
        Snapshot(
            replyMode: replyMode,
            combinedFollowers: combinedFollowers,
            combinedFollowing: combinedFollowing,
            combinedMention: combinedMention,
            preservedListRules: preservedListRules,
            quotesEnabled: quotesEnabled
        )
    }

    private func rollback(_ s: Snapshot) {
        replyMode = s.replyMode
        combinedFollowers = s.combinedFollowers
        combinedFollowing = s.combinedFollowing
        combinedMention = s.combinedMention
        preservedListRules = s.preservedListRules
        quotesEnabled = s.quotesEnabled
    }

    private func write(snapshot: Snapshot) async {
        let pref = buildPref()
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .postInteractionSettings(pref))
        } catch {
            logger.error("putPreferences(postInteractionSettings) failed: \(error.localizedDescription, privacy: .public)")
            rollback(snapshot)
            errorMessage = error.localizedDescription
        }
    }

    /// Translate the current UI state back to the lexicon pref shape.
    private func buildPref() -> PostInteractionSettingsPref {
        let allowRules: [ThreadgateAllowRule]?
        switch replyMode {
        case .anyone:
            allowRules = nil
        case .nobody:
            allowRules = []
        case .combined:
            var rules: [ThreadgateAllowRule] = []
            if combinedFollowers { rules.append(.follower) }
            if combinedFollowing { rules.append(.following) }
            if combinedMention { rules.append(.mention) }
            for uri in preservedListRules { rules.append(.list(uri)) }
            // Empty combined → fall back to "anyone" so we don't accidentally
            // ship a lockout. RN's form ends up at the same place: with no
            // boxes checked and the radio off, the dialog re-selects "Anyone".
            allowRules = rules.isEmpty ? nil : rules
        }
        let embedRules: [PostgateEmbeddingRule] = quotesEnabled ? [] : [.disable]
        return PostInteractionSettingsPref(
            threadgateAllowRules: allowRules,
            postgateEmbeddingRules: embedRules
        )
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

#Preview("PostInteractionSettingsScreen — Light") {
    NavigationStack {
        PostInteractionSettingsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("PostInteractionSettingsScreen — Dark") {
    NavigationStack {
        PostInteractionSettingsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
