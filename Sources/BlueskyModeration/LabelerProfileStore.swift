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
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            isSubscribed = prefs.savedFeeds.contains {
                $0.type == "labeler" && $0.value == labelerDID
            }
        } catch {
            logger.error("labeler load error: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    public func subscribe(labelerDID: String) async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            var feeds = prefs.savedFeeds
            guard !feeds.contains(where: { $0.type == "labeler" && $0.value == labelerDID }) else {
                isSubscribed = true
                return
            }
            feeds.append(SavedFeed(id: UUID().uuidString, type: "labeler", value: labelerDID, pinned: false))
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences",
                body: PutPreferencesRequest(savedFeeds: feeds)
            )
            isSubscribed = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func unsubscribe(labelerDID: String) async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences",
                params: [:]
            )
            let feeds = prefs.savedFeeds.filter { !($0.type == "labeler" && $0.value == labelerDID) }
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences",
                body: PutPreferencesRequest(savedFeeds: feeds)
            )
            isSubscribed = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
