import SwiftUI
import BlueskyCore
import BlueskyKit

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

/// Per-labeler content filter settings.
///
/// Mirrors RN's `ProfileLabelsSection` (`screens/Profile/Sections/Labels.tsx`)
/// applied across every subscribed labeler — the SwiftUI client collapses RN's
/// "global Bluesky labels under the Moderation hub" + "per-labeler labels under
/// each labeler's profile screen" into a single screen, since the per-row
/// behavior is identical.
///
/// Layout (matches RN visit order):
/// - Adult-content toggle in the first section.
/// - One `Section` per subscribed labeler. The Bluesky moderation service
///   (DID `did:plc:ar7c4by46qjdydhdevvrndac`) is pinned to the top so the
///   built-in `porn` / `sexual` / `nudity` / `graphic-media` rows appear
///   under "Bluesky Moderation".
/// - Each row is a label defined by that labeler (combining
///   `policies.labelValues` and `policies.labelValueDefinitions` — RN's
///   `interpretLabelValueDefinitions` plus a dedupe pass).
/// - Per-label `Picker` writes a `ContentLabelPref(label, visibility,
///   labelerDid)` via `putPreferences`.
/// - Adult-only labels (RN flag `adult`) are dimmed and locked to "Hide" when
///   the adult-content toggle is off.
public struct ContentFilterSettingsScreen: View {
    @State private var viewModel: ModerationViewModel

    /// The Bluesky moderation service DID. Used to pin Bluesky's built-in
    /// labels to the top of the screen and to look up the global porn /
    /// sexual / nudity / graphic-media rows. Mirrors RN's
    /// `BSKY_LABELER_DID` constant from `@atproto/api`.
    private static let blueskyLabelerDID: DID = DID(rawValue: "did:plc:ar7c4by46qjdydhdevvrndac")

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Adult Content", isOn: Binding(
                    get: { viewModel.adultContentEnabled },
                    set: { enabled in Task { await viewModel.setAdultContent(enabled: enabled) } }
                ))
            } header: {
                Text("Age-Restricted Content")
            } footer: {
                Text("Enabling adult content may reveal sexually explicit material.")
            }

            if viewModel.isLoadingLabelers && viewModel.subscribedLabelers.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading labelers…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(orderedLabelers, id: \.creator.did) { labeler in
                    labelerSection(for: labeler)
                }
            }
        }
        .navigationTitle("Content Filters")
        .task {
            await viewModel.loadPreferences()
            await viewModel.loadSubscribedLabelers()
        }
        .refreshable {
            await viewModel.loadPreferences()
            await viewModel.loadSubscribedLabelers()
        }
    }

    /// Bluesky Moderation pinned to the top, then any other subscribed
    /// labelers in the order the appview returned them. Matches RN's behavior
    /// of always rendering app-labelers first via
    /// `BskyAgent.appLabelers.concat(prefs.labelers)`.
    private var orderedLabelers: [LabelerView] {
        let all = viewModel.subscribedLabelers
        let bsky = all.filter { $0.creator.did == Self.blueskyLabelerDID }
        let others = all.filter { $0.creator.did != Self.blueskyLabelerDID }
        return bsky + others
    }

    @ViewBuilder
    private func labelerSection(for labeler: LabelerView) -> some View {
        let rows = labelRows(for: labeler)
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.identifier) { row in
                    LabelRow(
                        row: row,
                        labelerDID: labeler.creator.did,
                        adultContentEnabled: viewModel.adultContentEnabled,
                        currentVisibility: currentVisibility(
                            label: row.identifier,
                            labelerDID: labeler.creator.did,
                            defaultSetting: row.defaultSetting
                        ),
                        onSet: { newVisibility in
                            Task {
                                // Built-in Bluesky labels are stored as
                                // global preferences (`labelerDid == nil`)
                                // so RN clients on other devices read the
                                // same value. Custom labeler labels carry
                                // their owning DID. RN's
                                // `usePreferencesSetContentLabelMutation`
                                // uses the same split.
                                let did: DID? = labeler.creator.did == Self.blueskyLabelerDID ? nil : labeler.creator.did
                                await viewModel.setLabelVisibility(
                                    label: row.identifier,
                                    labelerDid: did,
                                    visibility: newVisibility
                                )
                            }
                        }
                    )
                }
            } header: {
                Text(labelerSectionTitle(for: labeler))
            }
        }
    }

    private func labelerSectionTitle(for labeler: LabelerView) -> String {
        if labeler.creator.did == Self.blueskyLabelerDID {
            return "Bluesky Moderation"
        }
        if let displayName = labeler.creator.displayName, !displayName.isEmpty {
            return displayName
        }
        return "@\(labeler.creator.handle.rawValue)"
    }

    /// Combines `policies.labelValues` (which includes built-in Bluesky
    /// values like `"porn"`) with `policies.labelValueDefinitions`
    /// (custom-labeler metadata) to produce the rows for one section.
    /// Built-in labels are matched against `Self.builtInLabelMetadata` for
    /// their display title, severity, and adult-only flag — RN's
    /// `LABELS` constant from `@atproto/api`.
    private func labelRows(for labeler: LabelerView) -> [LabelRowData] {
        guard let policies = labeler.policies else { return [] }

        // Custom defs keyed by identifier, preserving the labeler's own
        // metadata (severity, defaultSetting, adultOnly, etc).
        var customByIdentifier: [String: LabelValueDefinition] = [:]
        for def in policies.labelValueDefinitions {
            customByIdentifier[def.identifier] = def
        }

        // Dedupe `labelValues` while preserving order — mirrors RN's
        // `arr.indexOf(val) === i` filter in `Labels.tsx`.
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in policies.labelValues {
            if !seen.contains(value) {
                seen.insert(value)
                ordered.append(value)
            }
        }

        return ordered.compactMap { identifier -> LabelRowData? in
            // System / non-configurable labels (`!hide`, `!warn`, …) are
            // skipped. RN drops these via `def.configurable === false`.
            if identifier.hasPrefix("!") { return nil }

            if let custom = customByIdentifier[identifier] {
                return LabelRowData(
                    identifier: identifier,
                    title: identifier,
                    severity: custom.severity,
                    defaultSetting: custom.defaultSetting ?? "warn",
                    adultOnly: custom.adultOnly ?? false,
                    isCustom: true
                )
            }

            // Built-in label — pick up display metadata from the constant
            // table. Unknown values fall back to identifier-as-title.
            if let meta = Self.builtInLabelMetadata[identifier] {
                return LabelRowData(
                    identifier: identifier,
                    title: meta.title,
                    severity: meta.severity,
                    defaultSetting: meta.defaultSetting,
                    adultOnly: meta.adultOnly,
                    isCustom: false
                )
            }

            return LabelRowData(
                identifier: identifier,
                title: identifier,
                severity: "alert",
                defaultSetting: "warn",
                adultOnly: false,
                isCustom: false
            )
        }
    }

    /// Resolves the currently-saved visibility for `(label, labelerDID)`,
    /// falling back to the label's `defaultSetting` if no preference is
    /// stored. Built-in Bluesky labels are stored as global prefs
    /// (`labelerDid == nil`); custom labels carry their owning DID.
    private func currentVisibility(label: String, labelerDID: DID, defaultSetting: String) -> String {
        let prefDID: DID? = labelerDID == Self.blueskyLabelerDID ? nil : labelerDID
        if let pref = viewModel.contentLabels.first(where: { $0.label == label && $0.labelerDid == prefDID }) {
            // RN normalizes legacy `"show"` and stores `"ignore"` going
            // forward; we accept both at read time but write `"ignore"`
            // (see `LabelRow.normalizedVisibility`).
            return normalize(pref.visibility)
        }
        return normalize(defaultSetting)
    }

    private func normalize(_ raw: String) -> String {
        switch raw {
        case "show": return "ignore"
        default: return raw
        }
    }

    /// Display metadata for the global Bluesky labels. Mirrors RN's `LABELS`
    /// constant from `@atproto/api` — only the four adult-content-gated
    /// labels are listed here because the new Bluesky labeler returns its
    /// other labels via `policies.labelValueDefinitions` like any other
    /// labeler. Severity / blurs / adultOnly come from the same constant.
    private static let builtInLabelMetadata: [String: BuiltInLabelMeta] = [
        "porn": BuiltInLabelMeta(
            title: "Explicit Sexual Content",
            severity: "alert",
            defaultSetting: "hide",
            adultOnly: true
        ),
        "sexual": BuiltInLabelMeta(
            title: "Suggestive Content",
            severity: "alert",
            defaultSetting: "warn",
            adultOnly: true
        ),
        "nudity": BuiltInLabelMeta(
            title: "Non-Sexual Nudity",
            severity: "alert",
            defaultSetting: "ignore",
            adultOnly: true
        ),
        "graphic-media": BuiltInLabelMeta(
            title: "Graphic Media",
            severity: "alert",
            defaultSetting: "warn",
            adultOnly: false
        )
    ]

    private struct BuiltInLabelMeta {
        let title: String
        let severity: String
        let defaultSetting: String
        let adultOnly: Bool
    }
}

// MARK: - Row model

private struct LabelRowData {
    let identifier: String
    let title: String
    let severity: String
    let defaultSetting: String
    let adultOnly: Bool
    let isCustom: Bool
}

// MARK: - LabelRow

private struct LabelRow: View {
    let row: LabelRowData
    let labelerDID: DID
    let adultContentEnabled: Bool
    let currentVisibility: String
    let onSet: (String) -> Void

    /// `true` when this row is locked because the user has adult content
    /// turned off and the label is adult-gated. Mirrors RN's `adultDisabled`
    /// branch in `LabelerLabelPreference`.
    private var adultDisabled: Bool {
        row.adultOnly && !adultContentEnabled
    }

    /// `true` when the "warn" option doesn't make sense — RN drops it when
    /// `blurs === 'none' && severity === 'none'`. We approximate using
    /// severity alone since `LabelValueDefinition.blurs` is informational
    /// here and most values that meet RN's condition also have
    /// `severity === 'none'`.
    private var canWarn: Bool {
        row.severity != "none"
    }

    /// Adjusts the displayed visibility when adult content is off (forces
    /// "Hide") or when warn is unavailable but the saved value is "warn"
    /// (downgrade to "Show"). Matches RN's `prefAdjusted` calculation.
    private var adjustedVisibility: String {
        if adultDisabled { return "hide" }
        if !canWarn && currentVisibility == "warn" { return "ignore" }
        return currentVisibility
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                if adultDisabled {
                    Text("Adult content is disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { adjustedVisibility },
                set: { newValue in
                    guard !adultDisabled else { return }
                    onSet(newValue)
                }
            )) {
                Text("Hide").tag("hide")
                if canWarn {
                    Text("Warn").tag("warn")
                }
                Text("Show").tag("ignore")
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(adultDisabled)
        }
        .opacity(adultDisabled ? 0.6 : 1.0)
    }
}

// MARK: - Previews

#Preview("ContentFilterSettingsScreen — Light") {
    NavigationStack {
        ContentFilterSettingsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ContentFilterSettingsScreen — Dark") {
    NavigationStack {
        ContentFilterSettingsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
