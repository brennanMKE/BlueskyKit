import Foundation

/// Unified error type for AT Protocol / XRPC operations.
public enum ATError: Error, Sendable {
    /// A transport-level URL error.
    case network(URLError)
    /// An unexpected HTTP status code (not 200/4xx XRPC).
    case httpStatus(Int)
    /// No session is active; user must log in.
    case unauthenticated
    /// The access token has expired and could not be refreshed.
    case sessionExpired
    /// The server requires a TOTP factor token before completing login.
    case authFactorTokenRequired
    /// The server returned an XRPC error envelope (`error` + `message`).
    case xrpc(code: String, message: String)
    /// Response payload could not be decoded.
    case decodingFailed(String)
    /// Any other error; carries a human-readable description.
    case unknown(String)
    /// The device has no viable network path; the request was short-circuited
    /// without attempting a connection.
    case noNetwork
}

extension ATError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let e):          return e.localizedDescription
        case .httpStatus(let code):    return "Unexpected HTTP status: \(code)"
        case .unauthenticated:         return "You are not signed in."
        case .sessionExpired:          return "Your session has expired. Please sign in again."
        case .authFactorTokenRequired: return "Two-factor authentication token required."
        case .xrpc(_, let msg):        return msg.isEmpty ? "Server error" : msg
        case .decodingFailed(let d):   return "Response decoding failed: \(d)"
        case .unknown(let d):          return d
        case .noNetwork:               return "You're offline. Check your connection and try again."
        }
    }
}
