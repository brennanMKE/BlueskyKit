import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit
import BlueskyAuth

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "OnboardingModel"
)

/// Local-only preference key the app reads at boot to decide whether to show
/// the onboarding flow. Mirrors RN's `persisted.Schema['onboarding'].step` —
/// flipped to `true` once `StepFinished` finishes wiring up prefs / follows.
///
/// Note: this is intentionally per-device and supplemental to the server-side
/// `app.bsky.actor.defs#interestsPref`. The RN client also stores its
/// onboarding-completion locally rather than gating off the server pref.
public enum OnboardingPreferenceKey {
    public static let hasOnboarded = "bluesky.onboarding.hasCompleted"
}

/// Convenience wrapper around `PreferencesStore` so callers don't need to
/// know the key name. Returns `true` for an unset value (default behaviour)
/// so that existing logged-in users who upgrade into a build that ships the
/// onboarding flow are *not* re-routed through it. The signup path
/// explicitly flips this to `false` so brand-new accounts see the flow.
public func onboardingHasCompleted(_ preferences: any PreferencesStore) -> Bool {
    do {
        return try preferences.get(Bool.self, for: OnboardingPreferenceKey.hasOnboarded) ?? true
    } catch {
        logger.debug("hasOnboarded read failed: \(error.localizedDescription, privacy: .public)")
        return true
    }
}

/// Marks the local hasOnboarded flag as `false` so the onboarding flow runs
/// on the next render. The signup flow calls this immediately after a
/// successful `createAccount` — see `SignupFlowView`'s success callback.
public func markOnboardingPending(_ preferences: any PreferencesStore) {
    do {
        try preferences.set(false, for: OnboardingPreferenceKey.hasOnboarded)
    } catch {
        logger.error("markOnboardingPending write failed: \(error.localizedDescription, privacy: .public)")
    }
}

/// Marks the local hasOnboarded flag as `true`. Failures are swallowed:
/// there is no recovery path from a write error here, and the user already
/// completed the flow — the worst case is they see it again on the next launch.
public func setOnboardingCompleted(_ preferences: any PreferencesStore) {
    do {
        try preferences.set(true, for: OnboardingPreferenceKey.hasOnboarded)
    } catch {
        logger.error("hasOnboarded write failed: \(error.localizedDescription, privacy: .public)")
    }
}

@MainActor
@Observable
public final class OnboardingModel {

    public enum Step: Int, CaseIterable {
        case welcome, profile, interests, suggestedAccounts, finished

        public var title: String {
            switch self {
            case .welcome:           return "Welcome to Bluesky"
            case .profile:           return "Give your profile a face"
            case .interests:         return "What are your interests?"
            case .suggestedAccounts: return "Suggested for you"
            case .finished:          return "You're all set"
            }
        }

        public var subtitle: String? {
            switch self {
            case .welcome:           return "Let's set up your account in a few quick steps."
            case .profile:           return "Add a display name and a short bio. You can change these later."
            case .interests:         return "We'll use this to help customize your experience."
            case .suggestedAccounts: return "Follow a few accounts to fill out your home feed."
            case .finished:          return nil
            }
        }
    }

    public let session: SessionManager
    public let network: any NetworkClient
    public let accountStore: any AccountStore
    public let preferences: any PreferencesStore

    public var activeStep: Step = .welcome

    // Profile step
    public var displayName: String = ""
    public var bio: String = ""

    // Interests step
    public var selectedInterests: Set<String> = []

    // Suggested accounts state
    public var suggestedActors: [ProfileView] = []
    public var followedDIDs: Set<String> = []
    public var isLoadingSuggestions: Bool = false
    public var suggestionsError: String?
    public var selectedInterestTab: String?

    // Finishing state
    public var isFinishing: Bool = false
    public var finishingError: String?

    public init(
        session: SessionManager,
        network: any NetworkClient,
        accountStore: any AccountStore,
        preferences: any PreferencesStore
    ) {
        self.session = session
        self.network = network
        self.accountStore = accountStore
        self.preferences = preferences
        // Seed the display name from the handle so the field isn't empty.
        if let handle = session.currentAccount?.handle.rawValue {
            self.displayName = handle.split(separator: ".").first.map(String.init) ?? handle
        }
    }

    // MARK: - Step navigation

    public var canGoBack: Bool { activeStep != .welcome && activeStep != .finished }

    public var totalDisplayedSteps: Int {
        // Welcome through suggestedAccounts. The Finished card is a
        // success/value-prop screen — RN excludes it from the position counter.
        Step.allCases.count - 1
    }

    public func goNext() {
        guard let next = Step(rawValue: activeStep.rawValue + 1) else { return }
        activeStep = next
    }

    public func goBack() {
        guard activeStep != .welcome,
              let prev = Step(rawValue: activeStep.rawValue - 1) else { return }
        activeStep = prev
    }

    // MARK: - Suggested accounts

    /// Fetches per-interest suggested accounts via
    /// `app.bsky.unspecced.getSuggestedOnboardingUsers`. RN passes the
    /// selected interests via a topics header on the same endpoint; the
    /// `category` param scopes a single interest tab. We send only `category`
    /// here — the topics-header preferential weighting is a follow-up that
    /// requires plumbing custom headers through `NetworkClient`.
    public func loadSuggestedAccounts(category: String? = nil) async {
        isLoadingSuggestions = true
        suggestionsError = nil
        defer { isLoadingSuggestions = false }

        var params: [String: String] = ["limit": "10"]
        if let category, !category.isEmpty {
            params["category"] = category
        }
        do {
            let resp: GetSuggestedOnboardingUsersResponse = try await network.get(
                lexicon: "app.bsky.unspecced.getSuggestedOnboardingUsers",
                params: params
            )
            suggestedActors = resp.actors
        } catch {
            // Fall back to the cross-interest endpoint so the step is never
            // empty. RN does the same thing in `useSuggestedOnboardingUsers`
            // when the unspecced lexicon is unavailable on a given PDS.
            do {
                let fallback: GetSuggestionsResponse = try await network.get(
                    lexicon: "app.bsky.actor.getSuggestions",
                    params: ["limit": "20"]
                )
                suggestedActors = fallback.actors
            } catch {
                logger.error("suggested accounts load failed: \(error.localizedDescription, privacy: .public)")
                suggestionsError = error.localizedDescription
            }
        }
    }

    /// Fires off a `app.bsky.graph.follow` createRecord. We optimistically
    /// add the DID to `followedDIDs` so the UI updates immediately and revert
    /// on failure. The bulk-write parity with RN (`bulkWriteFollows` in
    /// `screens/Onboarding/util.ts`) is not yet ported — single follows are
    /// good enough for an onboarding pass.
    public func toggleFollow(_ profile: ProfileView) async {
        let didString = profile.did.rawValue
        if followedDIDs.contains(didString) || profile.viewer?.following != nil {
            // Onboarding follows are one-shot — we don't expose unfollow here.
            return
        }
        let viewerDID: DID
        do {
            guard let did = try await accountStore.loadCurrentDID() else { return }
            viewerDID = did
        } catch {
            logger.error("toggleFollow: load current DID failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        followedDIDs.insert(didString)
        let req = CreateRecordRequest(
            repo: viewerDID.rawValue,
            collection: "app.bsky.graph.follow",
            record: FollowRecord(subject: profile.did)
        )
        do {
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
            )
        } catch {
            logger.error("follow failed for \(didString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            followedDIDs.remove(didString)
        }
    }

    // MARK: - Finishing

    /// Bundles the work `StepFinished` does in RN: writes the interests pref,
    /// best-effort updates the profile record (display name + bio), then
    /// flips the local `hasOnboarded` flag and signals completion.
    /// All steps individually swallow their errors so one transient failure
    /// doesn't trap the user inside onboarding.
    public func finish() async -> Bool {
        isFinishing = true
        finishingError = nil
        defer { isFinishing = false }

        // 1. Write interests preference (server-side; seeds Discover).
        if !selectedInterests.isEmpty {
            do {
                let _: EmptyResponse = try await network.post(
                    lexicon: "app.bsky.actor.putPreferences",
                    body: PutPreferencesRequest(interests: Array(selectedInterests))
                )
            } catch {
                logger.error("interests pref write failed: \(error.localizedDescription, privacy: .public)")
                // Non-fatal — keep going.
            }
        }

        // 2. Best-effort profile record update (display name + bio). RN does
        //    this via `agent.upsertProfile`; we hit `com.atproto.repo.putRecord`
        //    directly, scoped to the `self` rkey on the profile collection.
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if let viewerDID = session.currentAccount?.did,
           !trimmedName.isEmpty || !trimmedBio.isEmpty {
            do {
                let req = PutRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.actor.profile",
                    rkey: "self",
                    record: ProfileRecord(
                        displayName: trimmedName.isEmpty ? nil : trimmedName,
                        description: trimmedBio.isEmpty ? nil : trimmedBio
                    )
                )
                let _: CreateRecordResponse = try await network.post(
                    lexicon: "com.atproto.repo.putRecord",
                    body: req
                )
            } catch {
                logger.error("profile upsert failed: \(error.localizedDescription, privacy: .public)")
                // Non-fatal — keep going.
            }
        }

        // 3. Flip local pref so RootView stops routing here.
        setOnboardingCompleted(preferences)

        return true
    }
}
