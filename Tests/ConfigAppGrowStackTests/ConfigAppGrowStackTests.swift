#if Config
import AppGrowStackCore
import ConfigAppGrowStack
import ConfigCore
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

func stack(_ http: FakeHTTP) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: .production, installID: "a1",
                 app: AppGrowStackApp(version: "2.4.0", build: "240", channel: .appStore, lang: "ja", region: "JP"),
                 storage: MemoryAppGrowStackStorage(), http: http)
}

let bundled = BundledConfigSetSource(data: Data(#"{"schema_version":1,"project":"reading-memory","version":0,"published_at":0,"flags":{}}"#.utf8))

struct ConfigAppGrowStackTests {
    @Test func fetchesTheSetWithTheETagAndTheClientHeader() async throws {
        let http = FakeHTTP([.success((200, #"{"version":4}"#, ["ETag": "\"v4\""])), .success((304, "", [:]))])
        let source = stack(http).configSource()
        #expect(try await source.fetch(etag: nil) == .fetched(Data(#"{"version":4}"#.utf8), etag: "\"v4\""))
        #expect(try await source.fetch(etag: "\"v4\"") == .notModified)

        let first = http.requests[0]
        #expect(first.httpMethod == "GET")
        #expect(first.url?.absoluteString == "https://api.appgrowstack.com/v1/config/sets/pk_KUdMabcdefghijklmnopqrst")
        #expect(first.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(first.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(first.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/2.4.0/swift-app-config/\(ConfigSDK.version)")
        #expect(http.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v4\"")
    }

    @Test func otherStatusesThrow() async {
        let source = stack(FakeHTTP([.success((503, "", [:]))])).configSource()
        await #expect(throws: ConfigSetFetchFailure(status: 503)) { try await source.fetch(etag: "\"v4\"") }
    }

    @Test func theBundledSetIsUsedOnlyUntilTheFirstFetch() async throws {
        let offline = stack(FakeHTTP([.failure(Offline()), .failure(Offline())])).configSource(fallback: bundled)
        #expect(try await offline.fetch(etag: nil) == .fetched(bundled.data!, etag: bundled.etag))
        await #expect(throws: Offline.self) { try await offline.fetch(etag: "\"v4\"") }
    }

    @Test func theContextComesFromTheStack() {
        let context = stack(FakeHTTP([])).configContext
        #expect(context.appVersion == "2.4.0")
        #expect(context.channel == "appstore")
        #expect(context.facts(now: context.firstSeenAt)["days_since_first_seen"] == .int(0))
        #expect(context.facts(now: context.firstSeenAt)["region"] == .string("JP"))
    }
}
#endif
