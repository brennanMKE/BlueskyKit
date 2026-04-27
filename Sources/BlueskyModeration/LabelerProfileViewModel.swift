import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class LabelerProfileViewModel {

    public var labeler: LabelerView? { store.labeler }
    public var isSubscribed: Bool { store.isSubscribed }
    public var isLoading: Bool { store.isLoading }
    public var isUpdating: Bool { store.isUpdating }
    public var error: String? { store.error }

    private let labelerDID: String
    private let store: any LabelerProfileStoring

    public init(labelerDID: String, network: any NetworkClient) {
        self.labelerDID = labelerDID
        self.store = LabelerProfileStore(network: network)
    }

    public func load() async { await store.load(labelerDID: labelerDID) }
    public func subscribe() async { await store.subscribe(labelerDID: labelerDID) }
    public func unsubscribe() async { await store.unsubscribe(labelerDID: labelerDID) }
}
