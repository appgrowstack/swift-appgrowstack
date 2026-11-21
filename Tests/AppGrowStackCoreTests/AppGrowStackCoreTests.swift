import AppGrowStackCore
import Foundation
import Testing

/// Records requests and answers every one with the same status and body.
final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answer: (Int, String) = (200, "{}")

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            requests.append(request)
            return answer
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

let app = AppGrowStackApp(version: "3.3.0", build: "120", channel: .appStore, lang: "ja", region: "JP")

func stack(
    environment: AppGrowStackEnvironment = .production,
    installID: String = "A1B2C3D4-0000-4000-8000-00000000000F",
    firstSeenAt: Date? = nil,
    storage: MemoryAppGrowStackStorage = MemoryAppGrowStackStorage(),
    http: FakeHTTP = FakeHTTP(),
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: environment, installID: installID,
                 firstSeenAt: firstSeenAt, app: app, storage: storage, http: http, now: { now })
}

struct AppGrowStackTests {
    @Test func installIDIsLowercasedAndIsThePerson() {
        let s = stack()
        #expect(s.installID == "a1b2c3d4-0000-4000-8000-00000000000f")
        #expect(s.person() == "a1b2c3d4-0000-4000-8000-00000000000f")
    }

    @Test func rootURLsPerEnvironment() {
        #expect(AppGrowStackEnvironment.production.baseURL.absoluteString == "https://api.appgrowstack.com")
        #expect(AppGrowStackEnvironment.staging.baseURL.absoluteString == "https://api-staging.appgrowstack.com")
        #expect(AppGrowStackEnvironment.local(URL(string: "http://127.0.0.1:8787")!).baseURL.absoluteString == "http://127.0.0.1:8787")
    }

    @Test func requestsCarryTheKeyAndTheClientHeader() async throws {
        let http = FakeHTTP()
        let s = stack(environment: .staging, http: http)
        let request = s.request("GET", "/v1/support/articles", query: [URLQueryItem(name: "lang", value: "zh-Hant")])
        _ = try await s.send(request)
        let sent = try #require(http.requests.first)
        #expect(sent.httpMethod == "GET")
        #expect(sent.url?.absoluteString == "https://api-staging.appgrowstack.com/v1/support/articles?lang=zh-Hant")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer pk_KUdMabcdefghijklmnopqrst")
        // contracts K2-5: <platform>/<app version>/<sdk>/<sdk version>
        #expect(sent.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/3.3.0/swift-appgrowstack/\(AppGrowStack.sdkVersion)")
        #expect(s.clientHeader.wholeMatch(of: /(ios|android)\/\d+\.\d+(\.\d+)?\/[a-z][a-z0-9-]{1,40}\/\d+\.\d+\.\d+/) != nil)
    }

    @Test func firstSeenIsTheEarliestAndIsKept() {
        let storage = MemoryAppGrowStackStorage()
        let first = stack(storage: storage, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(first.firstSeenAt == Date(timeIntervalSince1970: 1_800_000_000))

        // A later launch keeps the stored date.
        let later = stack(storage: storage, now: Date(timeIntervalSince1970: 1_900_000_000))
        #expect(later.firstSeenAt == Date(timeIntervalSince1970: 1_800_000_000))

        // An earlier date from the app (used before the SDK existed) replaces it.
        let backdated = stack(firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000), storage: storage)
        #expect(backdated.firstSeenAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(storage.firstSeenAt == Date(timeIntervalSince1970: 1_700_000_000))

        // A later date from the app does not.
        let ignored = stack(firstSeenAt: Date(timeIntervalSince1970: 1_750_000_000), storage: storage)
        #expect(ignored.firstSeenAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func versionIsCutToThreeParts() {
        #expect(AppGrowStackApp.current(channel: .debug, bundle: Bundle(for: FakeHTTP.self)).version.split(separator: ".").count <= 3)
    }
}

struct AppGrowStackActivityTests {
    @Test func keepsTheNewestWithinTheLimits() {
        let activity = AppGrowStackActivity()
        for i in 0 ..< 25 {
            activity.record(.init(name: "e\(i)", at: Date(timeIntervalSince1970: Double(i)), props: ["i": .int(i)]))
        }
        for i in 0 ..< 12 {
            activity.record(.init(campaign: "c\(i)", setVersion: 3, at: Date(timeIntervalSince1970: Double(i))))
        }
        #expect(activity.events.count == AppGrowStackActivity.eventLimit)
        #expect(activity.events.first?.name == "e24")
        #expect(activity.events.last?.name == "e5")
        #expect(activity.campaigns.count == AppGrowStackActivity.campaignLimit)
        #expect(activity.campaigns.first?.campaign == "c11")
    }
}
