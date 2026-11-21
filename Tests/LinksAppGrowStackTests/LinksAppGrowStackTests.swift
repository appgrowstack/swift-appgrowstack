#if Links
import AppGrowStackCore
import AppLinks
import Foundation
import LinksAppGrowStack
import Testing

final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answers: [Result<(Int, String), Error>]

    init(_ answers: [Result<(Int, String), Error>]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = lock.withLock { () -> Result<(Int, String), Error> in
            requests.append(request)
            return answers.isEmpty ? .success((500, "")) : answers.removeFirst()
        }
        let (status, body) = try next.get()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct Offline: Error {}

func stack(_ http: FakeHTTP) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: .staging, installID: "3F2A9C1E-0B7D-4E55-9A10-7C3D2B1A0F99",
                 app: AppGrowStackApp(version: "3.3.0", build: "1", channel: .appStore, lang: "ja"),
                 storage: MemoryAppGrowStackStorage(), http: http)
}

let clues = AttributionRequest(installID: "ignored", appVersion: "3.3.0", firstOpenAt: 1_800_000_000_000,
                               openedURL: "https://gohobishukan.com/l/Ab12Cd34", appleAdsToken: "ads-token")

struct LinksAppGrowStackTests {
    @Test func postsTheCluesWithTheStacksInstallID() async throws {
        let http = FakeHTTP([.success((200, #"{"matched_by":"opened_url","source":"x_post","medium":null,"campaign":"launch","code":"Ab12Cd34","ad":null}"#))])
        let answer = await stack(http).attributionResolver().resolve(clues)
        #expect(answer == .decided(Attribution(matchedBy: .openedURL, source: "x_post", campaign: "launch", code: "Ab12Cd34")))

        let sent = try #require(http.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.absoluteString == "https://api-staging.appgrowstack.com/v1/links/attributions")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer pk_KUdMabcdefghijklmnopqrst")
        #expect(sent.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/3.3.0/swift-appgrowstack/\(AppGrowStack.sdkVersion)")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["install_id"] as? String == "3f2a9c1e-0b7d-4e55-9a10-7c3d2b1a0f99")
        #expect(Set(body.keys) == ["install_id", "platform", "app_version", "first_open_at", "opened_url", "apple_ads_token"])
    }

    @Test func statusesMapToResolutions() async {
        #expect(await stack(FakeHTTP([.success((400, #"{"error":{"code":"invalid","message":"x"}}"#))])).attributionResolver().resolve(clues) == .rejected)
        #expect(await stack(FakeHTTP([.success((503, ""))])).attributionResolver().resolve(clues) == .retryLater)
        #expect(await stack(FakeHTTP([.success((429, ""))])).attributionResolver().resolve(clues) == .retryLater)
        #expect(await stack(FakeHTTP([.failure(Offline())])).attributionResolver().resolve(clues) == .retryLater)
    }

    @Test @MainActor func worksWithTheReporter() async {
        let http = FakeHTTP([.success((503, "")), .success((200, #"{"matched_by":"organic","source":"organic","medium":null,"campaign":null,"code":null,"ad":null}"#))])
        let s = stack(http)
        let defaults = UserDefaults(suiteName: "links-appgrowstack-tests-\(UUID().uuidString)")!
        let reporter = AttributionReporter(installID: s.installID, appVersion: "3.3.0", resolver: s.attributionResolver(),
                                           storage: UserDefaultsAttributionStorage(defaults: defaults), urlGrace: .milliseconds(1))
        #expect(await reporter.reportIfNeeded() == nil)
        #expect(await reporter.reportIfNeeded()?.matchedBy == .organic)
        #expect(http.requests.count == 2)
    }
}
#endif
