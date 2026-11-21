#if Campaign
import AppGrowStackCore
import CampaignAppGrowStack
import CampaignCore
import Foundation
import Testing

final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answers: [Result<(Int, String, [String: String]), Error>]

    init(_ answers: [Result<(Int, String, [String: String]), Error>]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = lock.withLock { () -> Result<(Int, String, [String: String]), Error> in
            requests.append(request)
            return answers.isEmpty ? .success((500, "", [:])) : answers.removeFirst()
        }
        let (status, body, headers) = try next.get()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

struct Offline: Error {}

/// `packages/contract` の APPGROWSTACK_CLIENT_PATTERN と同じ
private var clientPattern: Regex<(Substring, Substring, Substring?, Substring?)> { #/^(ios|android)\/\d+\.\d+(\.\d+)?\/[a-z][a-z0-9-]{1,40}\/\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/# }

func stack(_ http: FakeHTTP) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: .production, installID: "a1",
                 app: AppGrowStackApp(version: "3.3.0", build: "330", channel: .appStore, lang: "ja"),
                 storage: MemoryAppGrowStackStorage(), http: http)
}

let bundled = BundledCampaignSetFetcher(data: Data(#"{"version":1,"campaigns":[]}"#.utf8))

struct CampaignAppGrowStackTests {
    @Test func fetchesTheSetWithTheETagAndTheClientHeader() async throws {
        let http = FakeHTTP([.success((200, #"{"version":4}"#, ["ETag": "\"v4\""])), .success((304, "", [:]))])
        let source = stack(http).campaignSource()
        #expect(try await source.fetch(etag: nil) == .fetched(Data(#"{"version":4}"#.utf8), etag: "\"v4\""))
        #expect(try await source.fetch(etag: "\"v4\"") == .notModified)

        let first = http.requests[0]
        #expect(first.httpMethod == "GET")
        #expect(first.url?.absoluteString == "https://api.appgrowstack.com/v1/campaigns/sets/pk_KUdMabcdefghijklmnopqrst")
        #expect(first.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(first.value(forHTTPHeaderField: "If-None-Match") == nil)
        let client = try #require(first.value(forHTTPHeaderField: "AppGrowStack-Client"))
        #expect(client == "ios/3.3.0/swift-app-campaign/\(CampaignSDK.version)")
        #expect(client.wholeMatch(of: clientPattern) != nil)
        #expect(http.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v4\"")
    }

    @Test func contextCarriesTheBuildAndTheEarlierFirstSeenDate() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let storage = MemoryAppGrowStackStorage(firstSeenAt: Date(timeIntervalSince1970: 1_760_000_000))
        let stack = AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", installID: "a1", firstSeenAt: earlier,
                                 app: AppGrowStackApp(version: "3.3.0", build: "330", channel: .testFlight, lang: "ja", region: "JP"),
                                 storage: storage, http: FakeHTTP([]))
        let context = stack.campaignContext
        #expect(context == CampaignContext(platform: "ios", appVersion: "3.3.0", build: "330", channel: "testflight",
                                           lang: "ja", region: "JP", firstSeenAt: earlier))
    }

    @Test func otherStatusesThrow() async {
        let source = stack(FakeHTTP([.success((503, "", [:]))])).campaignSource()
        await #expect(throws: CampaignSetFetchFailure(status: 503)) { try await source.fetch(etag: "\"v4\"") }
    }

    @Test func theBundledSetIsUsedOnlyUntilTheFirstFetch() async throws {
        let offline = stack(FakeHTTP([.failure(Offline()), .failure(Offline())])).campaignSource(fallback: bundled)
        #expect(try await offline.fetch(etag: nil) == .fetched(Data(#"{"version":1,"campaigns":[]}"#.utf8), etag: bundled.etag))
        // A set on hand (an ETag) is kept instead: the failure goes to the engine.
        await #expect(throws: Offline.self) { try await offline.fetch(etag: "\"v4\"") }
        // Without a fallback the failure goes to the engine too.
        await #expect(throws: Offline.self) { try await stack(FakeHTTP([.failure(Offline())])).campaignSource().fetch(etag: nil) }
    }
}
#endif
