import Foundation

/// The current viability of the device's network path.
///
/// Defined in `BlueskyCore` (Layer 0) so all layers can reference it
/// without importing the `Network` framework.
public enum NetworkPathStatus: Sendable, Equatable {
    /// A viable path exists (Wi-Fi, Ethernet, or cellular).
    case viable
    /// No viable path. `reason` is a short human-readable hint (optional).
    case notViable(reason: String?)
}
