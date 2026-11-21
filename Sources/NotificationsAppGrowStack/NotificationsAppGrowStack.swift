#if Notifications
import AppGrowStackCore
import Foundation
import RemoteNotifications

/// Tells appgrowstack that a delivery was opened: `POST /v1/notify/opened` with `{"send_id": …}`.
/// Give ``report(sendID:)`` to `NotificationCenterDelegate(reportOpened:)`.
///
/// The server answers 204 even for a `send_id` it does not know, so any 2xx and any other 4xx
/// count as done (sending the same body again would not change the answer). A failed connection,
/// 429 and 5xx throw, so the app can retry.
public struct AppGrowStackNotificationOpenReporter: Sendable {
    let stack: AppGrowStack

    /// Thrown for 429 and 5xx.
    public struct Failure: Error, Equatable {
        public let status: Int

        public init(status: Int) { self.status = status }
    }

    public func report(sendID: String) async throws {
        var request = stack.request("POST", "/v1/notify/opened", sdk: NotificationsSDK.name, version: NotificationsSDK.version)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["send_id": sendID])
        let (_, response) = try await stack.send(request)
        if response.statusCode == 429 || response.statusCode >= 500 {
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
