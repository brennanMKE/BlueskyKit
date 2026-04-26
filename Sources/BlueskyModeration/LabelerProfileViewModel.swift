import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class LabelerProfileViewModel {
    public var labeler: LabelerView?
    public var isSubscribed = false
    public var isLoading = false
    public var isUpdating = false
    public var error: String?

    private let network: any NetworkClient
    private let labelerDID: String

    public init(labelerDID: String, network: any NetworkClient) {
        self.labelerDID = labelerDID
        self.network = network
    }

    public func load() async {
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
            self.error = error.localizedDescription
        }
    }

    public func subscribe() async {
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

    public func unsubscribe() async {
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
