#if Notifications
import AppGrowStackCore
import Foundation
import NotificationsAppGrowStack
import Testing

final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answers: [Result<Int, Error>]

    init(_ answers: [Result<Int, Error>]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = lock.withLock { () -> Result<Int, Error> in
            requests.append(request)
            return answers.isEmpty ? .success(500) : answers.removeFirst()
        }
        let status = try next.get()
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct Offline: Error {}

func stack(_ http: FakeHTTP) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: .production, installID: "A1B2",
                 app: AppGrowStackApp(version: "3.4.0", build: "340", channel: .appStore, lang: "ja"),
                 storage: MemoryAppGrowStackStorage(), http: http)
}

let sendID = "0f8e2b1c-3d4a-4b5c-8d6e-7f8091a2b3c4"

struct NotificationsAppGrowStackTests {
    @Test func postsTheSendIDWithThePublicKey() async throws {
        let http = FakeHTTP([.success(204)])
        try await stack(http).notificationOpenReporter().report(sendID: sendID)

        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.appgrowstack.com/v1/notify/opened")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pk_KUdMabcdefghijklmnopqrst")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/3.4.0/swift-appgrowstack/\(AppGrowStack.sdkVersion)")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["send_id": sendID])
    }

    @Test func aBodyThatWillNeverPassIsNotRetried() async throws {
        // 400 (a malformed send_id) answers the same every time: done, not thrown.
        try await stack(FakeHTTP([.success(400)])).notificationOpenReporter().report(sendID: "x")
    }

    @Test func busyServersAndNoConnectionThrow() async {
        await #expect(throws: AppGrowStackNotificationOpenReporter.Failure(status: 429)) {
            try await stack(FakeHTTP([.success(429)])).notificationOpenReporter().report(sendID: sendID)
        }
        await #expect(throws: AppGrowStackNotificationOpenReporter.Failure(status: 503)) {
            try await stack(FakeHTTP([.success(503)])).notificationOpenReporter().report(sendID: sendID)
        }
        await #expect(throws: Offline.self) {
            try await stack(FakeHTTP([.failure(Offline())])).notificationOpenReporter().report(sendID: sendID)
        }
    }
}
#endif
