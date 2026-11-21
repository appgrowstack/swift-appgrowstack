#if Notifications
import AppGrowStackCore
import Foundation
import RemoteNotifications

/// Tells appgrowstack that a delivery was opened: `POST /v1/notify/opened` with `{"send_id": …}`.
/// Give ``report(sendID:)`` to `NotificationCenterDelegate(reportOpened:)`.
///
/// The status is read with ``AppGrowStackAnswer``. The server answers 204 even for a `send_id` it
/// does not know, so any 2xx and a body that will never pass (400 and the other 4xx but 401, 403,
/// 408 and 429) count as done. A failed connection and the rest (401 and 403, 408, 429, 5xx) throw,
/// so `NotificationCenterDelegate` keeps the `send_id` and sends it again later.
public struct AppGrowStackNotificationOpenReporter: Sendable {
    let stack: AppGrowStack

    /// Thrown for an answer to send again later (401, 403, 408, 429, 5xx).
    public struct Failure: Error, Equatable {
        public let status: Int

        public init(status: Int) { self.status = status }
    }

    public func report(sendID: String) async throws {
        var request = stack.request("POST", "/v1/notify/opened", sdk: NotificationsSDK.name, version: NotificationsSDK.version)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["send_id": sendID])
        let (_, response) = try await stack.send(request)
        if AppGrowStackAnswer(status: response.statusCode) == .retryLater {
            throw Failure(status: response.statusCode)
        }
    }
}

extension AppGrowStack {
    /// The reporter for `NotificationCenterDelegate(reportOpened: { try await reporter.report(sendID: $0) })`.
    public func notificationOpenReporter() -> AppGrowStackNotificationOpenReporter {
        AppGrowStackNotificationOpenReporter(stack: self)
    }
}
#endif
