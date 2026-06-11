import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "LabelerProfileStore")

// MARK: - LabelerProfileStoring

public protocol LabelerProfileStoring: AnyObject, Observable, Sendable {
    var labeler: LabelerView? { get }
    var isSubscribed: Bool { get }
    var isLoading: Bool { get }
    var isUpdating: Bool { get }
    var error: String? { get }

    func load(labelerDID: String) async
    func subscribe(labelerDID: String) async
    func unsubscribe(labelerDID: String) async
}

// MARK: - LabelerProfileStore

@Observable
public final class LabelerProfileStore: LabelerProfileStoring {

    public private(set) var labeler: LabelerView?
    public private(set) var isSubscribed = false
    public private(set) var isLoading = false
    public private(set) var isUpdating = false
    public private(set) var error: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func load(labelerDID: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: GetLabelerServicesResponse = try await network.get(
                lexicon: "app.bsky.labeler.getServices",
                params: ["dids": labelerDID, "detailed": "false"]
            )
            labeler = response.views.first
            let did = DID(rawValue: labelerDID)
            if AppLabelers.contains(did) {
                // RN's `isLabelerSubscribed`: app labelers (the Bluesky
                // Moderation Service) are always-on and never stored in
                // `labelersPref`.
                isSubscribed = true
            } else {
                let prefs: GetPreferencesResponse = try await network.get(
                    lexicon: "app.bsky.actor.getPreferences",
                    params: [:]
                )
                isSubscribed = prefs.subscribedLabelerDIDs.contains(did)
            }
        } catch {
            logger.error("labeler load error: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    public func subscribe(labelerDID: String) async {
        let did = DID(rawValue: labelerDID)
        // App labelers are implicitly subscribed and never written to
        // `labelersPref` (RN hides the Subscribe button via `isAppLabeler`).
        guard !AppLabelers.contains(did) else {
            isSubscribed = true
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            // Read-modify-write (#0201): the mutation is computed from the
            // fresh server state inside the writer's serialized update, and
            // the put body carries the full merged preferences array.
            // Subscriptions live in `labelersPref.labelers` (#0202) — RN's
            // `agent.addLabeler(did)`.
            try await PreferencesWriter.shared.update(network: network) { prefs in
                let current = prefs.subscribedLabelerDIDs
                guard !current.contains(did) else {
                    return nil // already subscribed — skip the write
                }
                // RN's MAX_LABELERS guard in `useLabelerSubscriptionMutation`.
                guard current.count < AppLabelers.maxLabelers else {
                    throw ATError.unknown(
                        "You can only subscribe to \(AppLabelers.maxLabelers) labelers, and you've reached your limit."
                    )
                }
                return .labelers(dids: current + [did])
            }
            isSubscribed = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func unsubscribe(labelerDID: String) async {
        let did = DID(rawValue: labelerDID)
        // App labelers are always-on; there is nothing to unsubscribe (RN
        // never shows the Unsubscribe button for them).
        guard !AppLabelers.contains(did) else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            // Read-modify-write (#0201); RN's `agent.removeLabeler(did)`.
            try await PreferencesWriter.shared.update(network: network) { prefs in
                let current = prefs.subscribedLabelerDIDs
                guard current.contains(did) else {
                    return nil // not subscribed — skip the write
                }
                return .labelers(dids: current.filter { $0 != did })
            }
            isSubscribed = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
