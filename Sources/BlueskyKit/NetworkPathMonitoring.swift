import BlueskyCore

/// Observes the device's network path and vends a live status stream.
///
/// Implementations live in `BlueskyNetworking` (Layer 2). All requirements are
/// `nonisolated` so the protocol is usable from background actors and non-`@MainActor`
/// contexts without extra hops.
public protocol NetworkPathMonitoring: AnyObject, Sendable {
    /// Current path viability — a synchronous snapshot safe to read anywhere.
    nonisolated var isViable: Bool { get }

    /// Current status value — a synchronous snapshot.
    nonisolated var status: NetworkPathStatus { get }

    /// Infinite async stream of status changes. Each element is emitted whenever
    /// the underlying path transitions (viable to not viable, interface change, etc.).
    /// The stream never completes normally; cancel the consuming `Task` to stop it.
    nonisolated var statusStream: AsyncStream<NetworkPathStatus> { get }
}
