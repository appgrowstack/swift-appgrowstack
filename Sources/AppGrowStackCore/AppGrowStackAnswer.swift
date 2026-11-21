import Foundation

/// How every connector reads the status of an answer to a request it sends (one table, so a
/// connector never keeps what another drops).
///
/// | Status | Answer | What the connector does |
/// |---|---|---|
/// | 2xx | ``accepted`` | done |
/// | 401, 403 | ``retryLater`` | the key is unknown or the project is paused. That is fixed on the server, not on the device, so the same body passes later |
/// | 408, 429, 5xx | ``retryLater`` | the server is busy or waiting on a store |
/// | any other 4xx (400, 404, 409, 413, 422, …) | ``rejected`` | the body will never pass; sending it again on every launch would only add noise |
///
/// A failed connection is ``retryLater`` too. A connector that sends again keeps its own limit on
/// how many times (the attribution, the open records), so ``retryLater`` never means "forever".
public enum AppGrowStackAnswer: Sendable, Hashable {
    case accepted
    case retryLater
    case rejected

    public init(status: Int) {
        switch status {
        case 200 ..< 300: self = .accepted
        case 401, 403, 408, 429, 500...: self = .retryLater
        case 400 ..< 500: self = .rejected
        default: self = .retryLater
        }
    }
}
