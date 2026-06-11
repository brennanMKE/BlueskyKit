import SwiftUI
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "MutedWordsScreen"
)

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - MutedWordsScreen

/// Moderation → Muted Words & Tags.
///
/// Mirrors `Bluesky-ReactNative/src/components/dialogs/MutedWords.tsx`. The RN
/// surface is a modal dialog; on Apple platforms we render the same controls
/// as a settings-style screen pushed from the moderation hub. Persists via
/// `app.bsky.actor.defs#mutedWordsPref` inside `app.bsky.actor.putPreferences`.
///
/// Form mirrors RN exactly:
/// - Text field for the word or tag (sanitization is server-side; we send raw).
/// - Duration radio: Forever · 24 hours · 7 days · 30 days.
/// - Mute-in radio: Text & tags · Tags only.
/// - "Exclude users you follow" toggle.
/// - Submit button.
///
/// Existing entries appear below in reverse-chronological order (matches RN's
/// `[...mutedWords].reverse()`). Each row shows the value, the target ("in
/// text & tags" / "in tags"), an expiry pill (or "Expired"), and an
/// "Excludes users you follow" hint. A trailing destructive swipe action
/// removes the entry.
///
/// Feed-side filtering wiring is deferred — see issue #0132 Gotchas.
public struct MutedWordsScreen: View {

    @State private var model: MutedWordsViewModel
    @State private var draftValue: String = ""
    @State private var draftDuration: DurationOption = .forever
    @State private var draftTarget: TargetOption = .textAndTags
    @State private var draftExcludeFollowing: Bool = false
    @State private var formError: String?

    public init(network: any NetworkClient) {
        _model = State(initialValue: MutedWordsViewModel(network: network))
    }

    public var body: some View {
        Form {
            addEntrySection
            yourMutedWordsSection
        }
        .navigationTitle("Muted Words & Tags")
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

    // MARK: Add entry

    private var addEntrySection: some View {
        Section {
            TextField("Enter a word or tag", text: $draftValue)
                .textFieldStyle(.automatic)
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            #endif

            Picker("Duration", selection: $draftDuration) {
                ForEach(DurationOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }

            Picker("Mute in", selection: $draftTarget) {
                ForEach(TargetOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }

            Toggle("Exclude users you follow", isOn: $draftExcludeFollowing)

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if model.isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSaving || trimmedDraft.isEmpty)

            if let formError {
                Text(formError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Add muted words and tags")
        } footer: {
            Text("Posts can be muted based on their text, their tags, or both. We recommend avoiding common words that appear in many posts, since it can result in no posts being shown.")
        }
    }

    private var trimmedDraft: String {
        draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        let value = trimmedDraft
        guard !value.isEmpty else {
            formError = "Please enter a valid word, tag, or phrase to mute"
            return
        }
        formError = nil
        let targets = draftTarget.lexiconTargets
        let actorTarget: String? = draftExcludeFollowing ? "exclude-following" : "all"
        let expiresAt: Date? = draftDuration.expiryFromNow()
        let entry = MutedWord(
            value: value,
            targets: targets,
            actorTarget: actorTarget,
            expiresAt: expiresAt
        )
        await model.add(entry)
        if model.errorMessage == nil {
            draftValue = ""
            draftDuration = .forever
            draftTarget = .textAndTags
            draftExcludeFollowing = false
        }
    }

    // MARK: Existing entries

    private var yourMutedWordsSection: some View {
        Section {
            if model.isLoading && model.entries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if model.entries.isEmpty {
                Text("You haven't muted any words or tags yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(displayedEntries, id: \.identity) { item in
                    MutedWordRow(entry: item.entry)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await model.remove(item.entry) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Your muted words")
        }
    }

    /// Reverse the list so the most recently added entries surface first
    /// (mirrors RN's `[...mutedWords].reverse()`). The identity wrapper keeps
    /// SwiftUI happy even when entries lack a server `id`.
    private var displayedEntries: [DisplayItem] {
        model.entries.enumerated().map { idx, entry in
            DisplayItem(index: idx, entry: entry)
        }.reversed()
    }
}

// MARK: - Duration & target options

private enum DurationOption: String, CaseIterable, Identifiable {
    case forever
    case day
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forever: return "Forever"
        case .day: return "24 hours"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    /// Returns `nil` for `.forever`; otherwise an absolute expiration relative
    /// to `Date()`. Mirrors RN's `now + N * ONE_DAY` math.
    func expiryFromNow(now: Date = Date()) -> Date? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .forever: return nil
        case .day: return now.addingTimeInterval(day)
        case .sevenDays: return now.addingTimeInterval(7 * day)
        case .thirtyDays: return now.addingTimeInterval(30 * day)
        }
    }
}

private enum TargetOption: String, CaseIterable, Identifiable {
    /// `targets == ["tag", "content"]` — match in text and hashtags.
    case textAndTags
    /// `targets == ["tag"]` — match the value only as a hashtag.
    case tagsOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .textAndTags: return "Text & tags"
        case .tagsOnly: return "Tags only"
        }
    }

    /// RN always emits `"tag"` and conditionally adds `"content"` (see
    /// `MutedWords.tsx` `surfaces`). We follow the same shape.
    var lexiconTargets: [String] {
        switch self {
        case .textAndTags: return ["tag", "content"]
        case .tagsOnly: return ["tag"]
        }
    }
}

// MARK: - Row view

private struct MutedWordRow: View {

    let entry: MutedWord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(entry.value)
                    .font(.body.weight(.semibold))
                Text(targetSuffix)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let detail = secondaryDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var targetSuffix: String {
        if entry.targets.contains("content") {
            return "in text & tags"
        }
        return "in tags"
    }

    private var secondaryDetail: String? {
        var pieces: [String] = []
        if let expiresAt = entry.expiresAt {
            if entry.isExpired() {
                pieces.append("Expired")
            } else {
                pieces.append("Expires \(MutedWordsScreen.relativeDateFormatter.localizedString(for: expiresAt, relativeTo: Date()))")
            }
        }
        if entry.actorTarget == "exclude-following" {
            pieces.append("Excludes users you follow")
        }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }
}

// MARK: - Identity wrapper

/// SwiftUI `ForEach` needs stable per-row identity even when entries don't
/// carry a server `id`. Pair the entry with its (post-load) index in the
/// canonical list to dedupe duplicates by value.
private struct DisplayItem {
    let index: Int
    let entry: MutedWord

    var identity: String { "\(entry.value)#\(index)" }
}

// MARK: - View model

@MainActor
@Observable
public final class MutedWordsViewModel {

    public private(set) var entries: [MutedWord] = []
    public var isLoading = false
    public var isSaving = false
    public var errorMessage: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            self.entries = resp.mutedWords
        } catch {
            logger.error("getPreferences (mutedWords) failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Append `entry` to the local list and write the new array via
    /// `putPreferences`. Optimistic update with rollback on failure.
    public func add(_ entry: MutedWord) async {
        let previous = entries
        entries.append(entry)
        await write(rollback: previous)
    }

    /// Remove an existing entry (matched by `id` if available, otherwise by
    /// `value` + `targets`). Optimistic update with rollback on failure.
    public func remove(_ entry: MutedWord) async {
        let previous = entries
        if let id = entry.id {
            entries.removeAll { $0.id == id }
        } else if let idx = entries.firstIndex(where: {
            // Match on full identity (not just value+targets) and drop a single
            // entry: two entries can share value+targets but differ in
            // expiration / actor scope, and `removeAll { value && targets }`
            // deleted both (#0232).
            $0.value == entry.value
                && $0.targets == entry.targets
                && $0.expiresAt == entry.expiresAt
                && $0.actorTarget == entry.actorTarget
        }) {
            entries.remove(at: idx)
        }
        await write(rollback: previous)
    }

    private func write(rollback previous: [MutedWord]) async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Read-modify-write (#0201): merge into the full preferences array.
            try await PreferencesWriter.shared.update(network: network, .mutedWords(entries))
        } catch {
            logger.error("putPreferences(mutedWords) failed: \(error.localizedDescription, privacy: .public)")
            entries = previous
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Helpers

extension MutedWordsScreen {
    fileprivate static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

// MARK: - Previews

#Preview("MutedWordsScreen — Light") {
    NavigationStack {
        MutedWordsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("MutedWordsScreen — Dark") {
    NavigationStack {
        MutedWordsScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
