import Foundation
import Network
import BlueskyCore
import BlueskyKit

/// Production implementation of `NetworkPathMonitoring` backed by `NWPathMonitor`.
///
/// Create one shared instance at app boot and pass it through `BlueskyEnvironment`.
/// Call `start()` immediately after creation.
public final class NWPathMonitorAdapter: NetworkPathMonitoring, @unchecked Sendable {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "co.sstools.bluesky.network-path-monitor")

    /// Continuation for the AsyncStream. Stored so we can yield to it from the
    /// NWPathMonitor handler running on the dedicated queue.
    private let continuation: AsyncStream<NetworkPathStatus>.Continuation

    /// nonisolated storage backed by a lock so reads are safe from any context.
    private let lock = NSLock()
    private var _status: NetworkPathStatus = .viable  // optimistic default until first callback

    public nonisolated var isViable: Bool { status == .viable }

    public nonisolated var status: NetworkPathStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public nonisolated let statusStream: AsyncStream<NetworkPathStatus>

    public init() {
        var capturedContinuation: AsyncStream<NetworkPathStatus>.Continuation!
        self.statusStream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    /// Starts the underlying `NWPathMonitor`. Call once at app boot.
    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus = NetworkPathStatus(path)
            self.lock.lock()
            let changed = self._status != newStatus
            self._status = newStatus
            self.lock.unlock()
            if changed {
                self.continuation.yield(newStatus)
            }
        }
        monitor.start(queue: queue)
    }

    /// Cancels the monitor. Call when the app is terminating (optional in practice).
    public func stop() {
        monitor.cancel()
        continuation.finish()
    }
}

// MARK: - NWPath -> NetworkPathStatus mapping

private extension NetworkPathStatus {
    init(_ path: NWPath) {
        if path.status == .satisfied {
            self = .viable
        } else {
            let reason: String?
            switch path.status {
            case .unsatisfied:
                reason = "no network interface available"
            case .requiresConnection:
                reason = "connection required (captive portal?)"
            default:
                reason = nil
            }
            self = .notViable(reason: reason)
        }
    }
}
