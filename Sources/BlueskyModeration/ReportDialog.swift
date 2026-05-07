import SwiftUI
import BlueskyCore
import BlueskyKit

// MARK: - Subject

/// What is being reported. Mirrors RN's `ParsedReportSubject` but trimmed
/// to the cases the SwiftUI client currently supports:
///
///   * `.account(did)` — entire user / repo (`com.atproto.admin.defs#repoRef`).
///   * `.record(uri:cid:)` — a single record (post, list, feed, status,
///     starter pack — anything keyed by AT-URI + CID, encoded as
///     `com.atproto.repo.strongRef`).
///
/// Convo / message reports are not yet exposed and would be added as a third
/// case (RN: `chat.bsky.convo.defs#messageRef`).
public enum ReportSubjectKind: Sendable {
    case account(DID)
    case record(uri: ATURI, cid: CID)

    /// Subject-type discriminator used by RN to filter labelers
    /// (`subjectTypes` is one of `"account"`, `"record"`, `"chat"`).
    fileprivate var labelerSubjectType: String {
        switch self {
        case .account: return "account"
        case .record: return "record"
        }
    }

    /// NSID collection of the record being reported, or `nil` for account
    /// subjects. Used to filter labelers by `subjectCollections`.
    fileprivate var nsid: String? {
        switch self {
        case .account: return nil
        case .record(let uri, _): return uri.collection
        }
    }
}

// MARK: - Reason types

/// Categorized report reasons. Mirrors RN's `useReportOptions` from
/// `src/components/moderation/ReportDialog/utils/useReportOptions.ts`.
/// The `reasonType` strings are Ozone-namespaced
/// (`tools.ozone.report.defs#reason*`), with a backwards-compatible mapping
/// to the older `com.atproto.moderation.defs#reason*` codes for labelers
/// that haven't picked up the new lexicon yet.
public enum ReportCategoryKey: String, CaseIterable, Sendable {
    case childSafety
    case violencePhysicalHarm
    case sexualAdultContent
    case harassmentHate
    case misleading
    case ruleBreaking
    case selfHarm
    case other
}

public struct ReportOption: Sendable, Identifiable {
    public let title: String
    /// Ozone reason type, e.g. `"tools.ozone.report.defs#reasonHarassmentTroll"`.
    public let reason: String
    public var id: String { reason }
}

public struct ReportCategoryConfig: Sendable, Identifiable {
    public let key: ReportCategoryKey
    public let title: String
    public let description: String
    public let options: [ReportOption]
    public var id: ReportCategoryKey { key }
}

/// Static list of categories + sub-reasons. RN re-builds this every render
/// for `useLingui` localization; in SwiftUI we keep one instance and rely on
/// the surrounding view's `Locale`-aware string catalog when localization
/// lands.
enum ReportReasons {
    static let categories: [ReportCategoryConfig] = [
        ReportCategoryConfig(
            key: .misleading,
            title: "Misleading",
            description: "Spam or other inauthentic behavior or deception",
            options: [
                ReportOption(title: "Spam", reason: "tools.ozone.report.defs#reasonMisleadingSpam"),
                ReportOption(title: "Scam", reason: "tools.ozone.report.defs#reasonMisleadingScam"),
                ReportOption(title: "Fake account or bot", reason: "tools.ozone.report.defs#reasonMisleadingBot"),
                ReportOption(title: "Impersonation", reason: "tools.ozone.report.defs#reasonMisleadingImpersonation"),
                ReportOption(title: "False information about elections", reason: "tools.ozone.report.defs#reasonMisleadingElections"),
                ReportOption(title: "Other misleading content", reason: "tools.ozone.report.defs#reasonMisleadingOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .sexualAdultContent,
            title: "Adult content",
            description: "Unlabeled, abusive, or non-consensual adult content",
            options: [
                ReportOption(title: "Unlabeled adult content", reason: "tools.ozone.report.defs#reasonSexualUnlabeled"),
                ReportOption(title: "Adult sexual abuse content", reason: "tools.ozone.report.defs#reasonSexualAbuseContent"),
                ReportOption(title: "Non-consensual intimate imagery", reason: "tools.ozone.report.defs#reasonSexualNCII"),
                ReportOption(title: "Deepfake adult content", reason: "tools.ozone.report.defs#reasonSexualDeepfake"),
                ReportOption(title: "Animal sexual abuse", reason: "tools.ozone.report.defs#reasonSexualAnimal"),
                ReportOption(title: "Other sexual violence content", reason: "tools.ozone.report.defs#reasonSexualOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .harassmentHate,
            title: "Harassment or hate",
            description: "Abusive or discriminatory behavior",
            options: [
                ReportOption(title: "Trolling", reason: "tools.ozone.report.defs#reasonHarassmentTroll"),
                ReportOption(title: "Targeted harassment", reason: "tools.ozone.report.defs#reasonHarassmentTargeted"),
                ReportOption(title: "Hate speech", reason: "tools.ozone.report.defs#reasonHarassmentHateSpeech"),
                ReportOption(title: "Doxxing", reason: "tools.ozone.report.defs#reasonHarassmentDoxxing"),
                ReportOption(title: "Other harassing or hateful content", reason: "tools.ozone.report.defs#reasonHarassmentOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .violencePhysicalHarm,
            title: "Violence",
            description: "Violent or threatening content",
            options: [
                ReportOption(title: "Animal welfare", reason: "tools.ozone.report.defs#reasonViolenceAnimal"),
                ReportOption(title: "Threats or incitement", reason: "tools.ozone.report.defs#reasonViolenceThreats"),
                ReportOption(title: "Graphic violent content", reason: "tools.ozone.report.defs#reasonViolenceGraphicContent"),
                ReportOption(title: "Glorification of violence", reason: "tools.ozone.report.defs#reasonViolenceGlorification"),
                ReportOption(title: "Extremist content", reason: "tools.ozone.report.defs#reasonViolenceExtremistContent"),
                ReportOption(title: "Human trafficking", reason: "tools.ozone.report.defs#reasonViolenceTrafficking"),
                ReportOption(title: "Other violent content", reason: "tools.ozone.report.defs#reasonViolenceOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .childSafety,
            title: "Child safety",
            description: "Harming or endangering minors",
            options: [
                ReportOption(title: "Child Sexual Abuse Material (CSAM)", reason: "tools.ozone.report.defs#reasonChildSafetyCSAM"),
                ReportOption(title: "Grooming or predatory behavior", reason: "tools.ozone.report.defs#reasonChildSafetyGroom"),
                ReportOption(title: "Privacy violation of a minor", reason: "tools.ozone.report.defs#reasonChildSafetyPrivacy"),
                ReportOption(title: "Minor harassment or bullying", reason: "tools.ozone.report.defs#reasonChildSafetyHarassment"),
                ReportOption(title: "Other child safety issue", reason: "tools.ozone.report.defs#reasonChildSafetyOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .selfHarm,
            title: "Self-harm or dangerous behaviors",
            description: "Harmful or high-risk activities",
            options: [
                ReportOption(title: "Content promoting or depicting self-harm", reason: "tools.ozone.report.defs#reasonSelfHarmContent"),
                ReportOption(title: "Eating disorders", reason: "tools.ozone.report.defs#reasonSelfHarmED"),
                ReportOption(title: "Dangerous challenges or activities", reason: "tools.ozone.report.defs#reasonSelfHarmStunts"),
                ReportOption(title: "Dangerous substances or drug abuse", reason: "tools.ozone.report.defs#reasonSelfHarmSubstances"),
                ReportOption(title: "Other dangerous content", reason: "tools.ozone.report.defs#reasonSelfHarmOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .ruleBreaking,
            title: "Breaking site rules",
            description: "Banned activities or security violations",
            options: [
                ReportOption(title: "Hacking or system attacks", reason: "tools.ozone.report.defs#reasonRuleSiteSecurity"),
                ReportOption(title: "Promoting or selling prohibited items or services", reason: "tools.ozone.report.defs#reasonRuleProhibitedSales"),
                ReportOption(title: "Banned user returning", reason: "tools.ozone.report.defs#reasonRuleBanEvasion"),
                ReportOption(title: "Other network rule-breaking", reason: "tools.ozone.report.defs#reasonRuleOther"),
            ]
        ),
        ReportCategoryConfig(
            key: .other,
            title: "Other",
            description: "An issue not included in these options",
            options: [
                ReportOption(title: "Other", reason: "tools.ozone.report.defs#reasonOther"),
            ]
        ),
    ]
}

/// Maps an Ozone-namespaced reason type to the legacy
/// `com.atproto.moderation.defs#reason*` value. Mirrors
/// `NEW_TO_OLD_REASONS_MAP` in RN's `const.ts`. Used to decide which
/// reasonType to actually send to a given labeler — we prefer the new value,
/// but fall back to the legacy code if the labeler only declares old types.
private let newToOldReasonMap: [String: String] = [
    "tools.ozone.report.defs#reasonAppeal": "com.atproto.moderation.defs#reasonAppeal",
    "tools.ozone.report.defs#reasonOther": "com.atproto.moderation.defs#reasonOther",

    "tools.ozone.report.defs#reasonViolenceAnimal": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceThreats": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceGraphicContent": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceGlorification": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceExtremistContent": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceTrafficking": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonViolenceOther": "com.atproto.moderation.defs#reasonViolation",

    "tools.ozone.report.defs#reasonSexualAbuseContent": "com.atproto.moderation.defs#reasonSexual",
    "tools.ozone.report.defs#reasonSexualNCII": "com.atproto.moderation.defs#reasonSexual",
    "tools.ozone.report.defs#reasonSexualDeepfake": "com.atproto.moderation.defs#reasonSexual",
    "tools.ozone.report.defs#reasonSexualAnimal": "com.atproto.moderation.defs#reasonSexual",
    "tools.ozone.report.defs#reasonSexualUnlabeled": "com.atproto.moderation.defs#reasonSexual",
    "tools.ozone.report.defs#reasonSexualOther": "com.atproto.moderation.defs#reasonSexual",

    "tools.ozone.report.defs#reasonChildSafetyCSAM": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonChildSafetyGroom": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonChildSafetyPrivacy": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonChildSafetyHarassment": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonChildSafetyOther": "com.atproto.moderation.defs#reasonViolation",

    "tools.ozone.report.defs#reasonHarassmentTroll": "com.atproto.moderation.defs#reasonRude",
    "tools.ozone.report.defs#reasonHarassmentTargeted": "com.atproto.moderation.defs#reasonRude",
    "tools.ozone.report.defs#reasonHarassmentHateSpeech": "com.atproto.moderation.defs#reasonRude",
    "tools.ozone.report.defs#reasonHarassmentDoxxing": "com.atproto.moderation.defs#reasonRude",
    "tools.ozone.report.defs#reasonHarassmentOther": "com.atproto.moderation.defs#reasonRude",

    "tools.ozone.report.defs#reasonMisleadingBot": "com.atproto.moderation.defs#reasonMisleading",
    "tools.ozone.report.defs#reasonMisleadingImpersonation": "com.atproto.moderation.defs#reasonMisleading",
    "tools.ozone.report.defs#reasonMisleadingSpam": "com.atproto.moderation.defs#reasonSpam",
    "tools.ozone.report.defs#reasonMisleadingScam": "com.atproto.moderation.defs#reasonMisleading",
    "tools.ozone.report.defs#reasonMisleadingElections": "com.atproto.moderation.defs#reasonMisleading",
    "tools.ozone.report.defs#reasonMisleadingOther": "com.atproto.moderation.defs#reasonMisleading",

    "tools.ozone.report.defs#reasonRuleSiteSecurity": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonRuleProhibitedSales": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonRuleBanEvasion": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonRuleOther": "com.atproto.moderation.defs#reasonViolation",

    "tools.ozone.report.defs#reasonSelfHarmContent": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonSelfHarmED": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonSelfHarmStunts": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonSelfHarmSubstances": "com.atproto.moderation.defs#reasonViolation",
    "tools.ozone.report.defs#reasonSelfHarmOther": "com.atproto.moderation.defs#reasonViolation",
]

/// Reasons that always route to Bluesky's labeler regardless of the user's
/// subscribed labeler set. Mirrors RN's `BSKY_LABELER_ONLY_REPORT_REASONS`.
private let bskyOnlyReasons: Set<String> = [
    "tools.ozone.report.defs#reasonChildSafetyCSAM",
    "tools.ozone.report.defs#reasonChildSafetyGroom",
    "tools.ozone.report.defs#reasonChildSafetyOther",
    "tools.ozone.report.defs#reasonViolenceExtremistContent",
]

/// Reasons that should auto-open the optional details textarea, matching
/// RN's `OTHER_REPORT_REASONS` set.
private let otherDetailReasons: Set<String> = [
    "tools.ozone.report.defs#reasonViolenceOther",
    "tools.ozone.report.defs#reasonSexualOther",
    "tools.ozone.report.defs#reasonChildSafetyOther",
    "tools.ozone.report.defs#reasonHarassmentOther",
    "tools.ozone.report.defs#reasonMisleadingOther",
    "tools.ozone.report.defs#reasonRuleOther",
    "tools.ozone.report.defs#reasonSelfHarmOther",
    "tools.ozone.report.defs#reasonOther",
]

/// Bluesky's official moderation labeler DID. Reports for child-safety and
/// extremist content always proxy here regardless of which labelers the user
/// has subscribed. RN exposes the same constant as `BSKY_LABELER_DID`.
private let blueskyLabelerDID = DID(rawValue: "did:plc:ar7c4by46qjdydhdevvrndac")

// MARK: - ReportDialog

public struct ReportDialog: View {
    private let subject: ReportSubjectKind
    private let availableLabelers: [LabelerView]
    private let onSubmit: (_ reasonType: String, _ reason: String?, _ labelerDID: DID?) async throws -> Void
    private let onDismiss: () -> Void

    @State private var selectedCategory: ReportCategoryConfig?
    @State private var selectedOption: ReportOption?
    @State private var selectedLabeler: LabelerView?
    @State private var detailsOpen = false
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    /// Backwards-compatible initializer. Existing call sites pass a
    /// `(reasonType, reason)` callback; we forward to the labeler-aware
    /// shape with `labelerDID = nil` (header proxy is then a no-op).
    /// Available labelers default to empty so the dialog falls back to a
    /// single Bluesky-only path.
    public init(
        subject: ReportSubjectKind,
        availableLabelers: [LabelerView] = [],
        onSubmit: @escaping (_ reasonType: String, _ reason: String?) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.subject = subject
        self.availableLabelers = availableLabelers
        self.onSubmit = { reasonType, reason, _ in try await onSubmit(reasonType, reason) }
        self.onDismiss = onDismiss
    }

    /// Labeler-aware initializer. The submit callback receives the chosen
    /// labeler DID so the caller can attach the `atproto-proxy` header.
    public init(
        subject: ReportSubjectKind,
        availableLabelers: [LabelerView],
        onSubmit: @escaping (_ reasonType: String, _ reason: String?, _ labelerDID: DID?) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.subject = subject
        self.availableLabelers = availableLabelers
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    if let category = selectedCategory {
                        chosenRow(title: category.title, subtitle: category.description) {
                            resetCategory()
                        }
                    } else {
                        ForEach(ReportReasons.categories) { category in
                            categoryRow(category)
                        }
                    }
                }

                if let category = selectedCategory, category.options.count > 1 {
                    Section("Select a reason") {
                        if let option = selectedOption {
                            chosenRow(title: option.title, subtitle: nil) {
                                resetOption()
                            }
                        } else {
                            ForEach(category.options) { option in
                                optionRow(option)
                            }
                        }
                    }
                }

                if let option = selectedOption, !candidateLabelers.isEmpty {
                    if candidateLabelers.count == 1, let only = candidateLabelers.first {
                        // Single labeler — auto-pick, don't show a chooser.
                        Section("Moderation service") {
                            labelerRow(only, isSelected: true) {}
                        }
                        // Auto-select on appear via task — kept idempotent.
                        Color.clear.frame(height: 0)
                            .task(id: option.reason) {
                                if selectedLabeler == nil {
                                    selectedLabeler = only
                                    detailsOpen = otherDetailReasons.contains(option.reason)
                                }
                            }
                    } else {
                        Section("Select moderation service") {
                            if let chosen = selectedLabeler {
                                labelerRow(chosen, isSelected: true) {
                                    selectedLabeler = nil
                                }
                            } else {
                                ForEach(candidateLabelers, id: \.creator.did) { labeler in
                                    labelerRow(labeler, isSelected: false) {
                                        selectedLabeler = labeler
                                        detailsOpen = otherDetailReasons.contains(option.reason)
                                    }
                                }
                            }
                        }
                    }
                } else if let option = selectedOption, candidateLabelers.isEmpty {
                    Section {
                        Text("None of your subscribed labelers handles this report type.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        // We still let the user submit without proxying; the
                        // PDS will route to its default labeler. This matches
                        // RN's fallback Admonition path.
                        Color.clear.frame(height: 0)
                            .task(id: option.reason) {
                                detailsOpen = otherDetailReasons.contains(option.reason)
                            }
                    }
                }

                if canShowDetailsStep {
                    Section {
                        if !detailsOpen {
                            Button("Add more details (optional)") {
                                detailsOpen = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Additional details (optional)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $details)
                                    .frame(minHeight: 80)
                                Text("\(details.count) / 300")
                                    .font(.caption)
                                    .foregroundStyle(details.count > 300 ? .red : .secondary)
                            }
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(didSubmit ? "Sent" : "Submit") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isSubmitting || didSubmit)
                }
            }
            .overlay {
                if isSubmitting { ProgressView() }
            }
            .alert("Report Submitted", isPresented: $didSubmit) {
                Button("OK") { onDismiss() }
            } message: {
                Text("Thank you for your report.")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func categoryRow(_ category: ReportCategoryConfig) -> some View {
        Button {
            selectCategory(category)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.body.weight(.semibold))
                Text(category.description).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func optionRow(_ option: ReportOption) -> some View {
        Button {
            selectedOption = option
            detailsOpen = otherDetailReasons.contains(option.reason)
            // Reset labeler selection so the picker re-runs against the new
            // candidate set.
            selectedLabeler = nil
        } label: {
            HStack {
                Text(option.title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func labelerRow(_ labeler: LabelerView, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(labeler.creator.displayName ?? labeler.creator.handle.rawValue)
                        .font(.body.weight(.semibold))
                    Text("By @\(labeler.creator.handle.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chosenRow(title: String, subtitle: String?, onClear: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change selection")
        }
    }

    // MARK: - State helpers

    private var navigationTitle: String {
        switch subject {
        case .account: return "Report this user"
        case .record(let uri, _):
            switch uri.collection {
            case "app.bsky.feed.post": return "Report this post"
            case "app.bsky.graph.list": return "Report this list"
            case "app.bsky.feed.generator": return "Report this feed"
            case "app.bsky.graph.starterpack": return "Report this starter pack"
            default: return "Report"
            }
        }
    }

    private func selectCategory(_ category: ReportCategoryConfig) {
        selectedCategory = category
        // RN: when "Other" is picked, jump straight to the (single) reason —
        // there's only one option under it.
        if category.key == .other, let only = category.options.first {
            selectedOption = only
            detailsOpen = otherDetailReasons.contains(only.reason)
        } else if category.options.count == 1, let only = category.options.first {
            selectedOption = only
            detailsOpen = otherDetailReasons.contains(only.reason)
        } else {
            selectedOption = nil
        }
        selectedLabeler = nil
    }

    private func resetCategory() {
        selectedCategory = nil
        selectedOption = nil
        selectedLabeler = nil
        detailsOpen = false
    }

    private func resetOption() {
        selectedOption = nil
        selectedLabeler = nil
        detailsOpen = false
    }

    /// Labelers that can accept the current subject + reason. Mirrors RN's
    /// `supportedLabelers` memo: filter by `subjectTypes`, by
    /// `subjectCollections`, then by `reasonTypes` (with the legacy fallback).
    /// Reasons in `bskyOnlyReasons` collapse to Bluesky's official labeler.
    private var candidateLabelers: [LabelerView] {
        guard let option = selectedOption else { return [] }

        // CSAM / extremist content always go to Bluesky.
        if bskyOnlyReasons.contains(option.reason) {
            if let bsky = availableLabelers.first(where: { $0.creator.did == blueskyLabelerDID }) {
                return [bsky]
            }
            return []
        }

        return availableLabelers.filter { labeler in
            // Subject type filter (account / record / chat). `nil` = all.
            if let types = labeler.subjectTypes, !types.isEmpty {
                if !types.contains(subject.labelerSubjectType) { return false }
            }

            // Collection filter (NSID). `nil` = all.
            if let collections = labeler.subjectCollections, !collections.isEmpty {
                if let nsid = subject.nsid, !collections.contains(nsid) { return false }
            }

            // Reason-type filter. `nil` = labeler accepts any reason.
            if let reasons = labeler.reasonTypes {
                let new = option.reason
                let legacy = newToOldReasonMap[new]
                if !reasons.contains(new), !(legacy.map { reasons.contains($0) } ?? false) {
                    return false
                }
            }

            return true
        }
    }

    private var canShowDetailsStep: Bool {
        guard selectedOption != nil else { return false }
        if candidateLabelers.isEmpty { return true }
        if candidateLabelers.count == 1 { return selectedLabeler != nil || true }
        return selectedLabeler != nil
    }

    private var canSubmit: Bool {
        guard selectedOption != nil else { return false }
        if !candidateLabelers.isEmpty && candidateLabelers.count > 1 {
            return selectedLabeler != nil
        }
        return true
    }

    // MARK: - Submit

    /// Picks the actual reason-type string to send. If the chosen labeler
    /// declares only the legacy code, swap to that for backwards compat —
    /// otherwise prefer the new Ozone code. Mirrors RN's branch in
    /// `useSubmitReportMutation`.
    private func resolvedReasonType(for option: ReportOption, labeler: LabelerView?) -> String {
        guard let labeler, let supported = labeler.reasonTypes, !supported.isEmpty else {
            return option.reason
        }
        let new = option.reason
        if supported.contains(new) { return new }
        if let legacy = newToOldReasonMap[new], supported.contains(legacy) { return legacy }
        return new
    }

    private func submit() async {
        guard let option = selectedOption else { return }
        let labeler = selectedLabeler
            ?? (candidateLabelers.count == 1 ? candidateLabelers.first : nil)
        let reasonType = resolvedReasonType(for: option, labeler: labeler)
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = trimmed.isEmpty ? nil : trimmed

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            try await onSubmit(reasonType, reason, labeler?.creator.did)
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
