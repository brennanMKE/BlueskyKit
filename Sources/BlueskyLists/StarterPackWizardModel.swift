import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit

private let starterPackWizardLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "StarterPackWizardModel"
)

/// State container for the multi-step Starter Pack create wizard.
///
/// Mirrors RN's `screens/StarterPack/Wizard/State.tsx` reducer / context:
/// the four steps share one mutable bag of selected profiles, selected
/// feeds, and details (name + description). Each step view binds to the
/// same model so navigation between steps preserves user input.
///
/// The RN reducer uses three steps (`Details`, `Profiles`, `Feeds`); the
/// SwiftUI port adds a `Preview` step before submit so the user can confirm
/// their pack before the network round-trip. RN shows the equivalent recap
/// inline in the Feeds-step footer; the dedicated screen is friendlier on
/// macOS where the wizard is presented as a sheet.
@MainActor
@Observable
public final class StarterPackWizardModel {

    public enum Step: Int, CaseIterable, Sendable {
        case profiles
        case feeds
        case details
        case preview

        public var title: String {
            switch self {
            case .profiles: return "Choose People"
            case .feeds: return "Choose Feeds"
            case .details: return "Starter Pack"
            case .preview: return "Preview"
            }
        }
    }

    public static let maxProfiles = 50
    public static let maxFeeds = 3

    public var currentStep: Step = .profiles
    public var selectedProfiles: [ProfileBasic] = []
    public var selectedFeeds: [GeneratorView] = []
    public var name: String = ""
    public var nameWasEdited: Bool = false
    public var description: String = ""
    public var processing: Bool = false
    public var errorMessage: String?
    /// Default name suggested in the Details step when the user hasn't typed
    /// one yet — RN seeds this from the current account's display name. Set
    /// once on wizard appear if the host has the profile.
    public var suggestedName: String = ""

    public init() {}

    // MARK: - Navigation

    public func canAdvance(from step: Step) -> Bool {
        switch step {
        case .profiles:
            // RN gates Profiles "Next" until at least 7 others (8 incl. self)
            // are selected. We mirror that minimum.
            return selectedProfiles.count >= 8
        case .feeds:
            // Feeds may be skipped — Next is always allowed.
            return true
        case .details:
            // Either typed name or suggested fallback; both produce a non-
            // empty record. We accept anything as long as the model can
            // resolve a name.
            return !effectiveName.trimmingCharacters(in: .whitespaces).isEmpty
        case .preview:
            return true
        }
    }

    public func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    public func goBack() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // MARK: - Profiles

    public func toggleProfile(_ profile: ProfileBasic) {
        if let index = selectedProfiles.firstIndex(where: { $0.did == profile.did }) {
            selectedProfiles.remove(at: index)
        } else {
            guard selectedProfiles.count < Self.maxProfiles else {
                errorMessage = "You can include at most \(Self.maxProfiles) people."
                return
            }
            selectedProfiles.append(profile)
        }
    }

    public func isProfileSelected(_ did: DID) -> Bool {
        selectedProfiles.contains { $0.did == did }
    }

    // MARK: - Feeds

    public func toggleFeed(_ feed: GeneratorView) {
        if let index = selectedFeeds.firstIndex(where: { $0.uri == feed.uri }) {
            selectedFeeds.remove(at: index)
        } else {
            guard selectedFeeds.count < Self.maxFeeds else {
                errorMessage = "You can include at most \(Self.maxFeeds) feeds."
                return
            }
            selectedFeeds.append(feed)
        }
    }

    public func isFeedSelected(_ uri: ATURI) -> Bool {
        selectedFeeds.contains { $0.uri == uri }
    }

    // MARK: - Details

    /// Resolved name to send with the record — RN slices to 50 chars and
    /// falls back to the suggested name when the field is blank.
    public var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? suggestedName : trimmed
        return String(resolved.prefix(50))
    }

    public var effectiveDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func clearError() { errorMessage = nil }
}
