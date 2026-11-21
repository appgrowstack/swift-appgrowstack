#if Support
import AppGrowStackCore
import Foundation
import SupportAppGrowStack
import SupportCore
import Testing

/// Records requests and answers from a table of (method path) → (status, body).
final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answers: [String: (Int, String)] = [:]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path())"
        let answer = lock.withLock { () -> (Int, String)? in
            requests.append(request)
            return answers[key]
        }
        guard let (status, body) = answer else { throw URLError(.notConnectedToInternet) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func json(_ i: Int) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: requests[i].httpBody ?? Data()) as! [String: Any]
    }
}

let ticketJSON = #"{"tickets":[{"ticket_id":"tkt_0123456789abcdef","status":"answered","subject":null,"created_at":1700000000000,"updated_at":1700000100000,"messages":[{"id":"msg_0123456789abcdef","from":"user","body":"解約したい","at":1700000000000},{"id":"msg_fedcba9876543210","from":"support","body":"App Store で解約できます","at":1700000100000}]}]}"#
let articlesJSON = #"{"articles":[{"slug":"cancel-subscription","lang":"ja","title":"サブスクリプションを解約する","summary":"iPhoneはApp Store、AndroidはGoogle Playで解約します。","url":"https://gohobishukan.com/help/cancel-subscription/","tags":["billing"],"updated_at":1}]}"#

func stack(_ http: FakeHTTP, environment: AppGrowStackEnvironment = .production) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: environment, installID: "A1B2C3D4-0000-4000-8000-000000000001",
                 app: AppGrowStackApp(version: "3.2.0", build: "120", channel: .appStore, lang: "ja"),
                 storage: MemoryAppGrowStackStorage(), http: http)
}

func context() -> SupportContext {
    SupportContext(appVersion: "3.2.0", build: "120", osVersion: "26.1", deviceModel: "iPhone17,1", channel: .appStore, isPremium: true,
                   sessionID: "ses_0123456789abcdef", screen: "settings")
}

struct SupportAppGrowStackTests {
    @Test func submitSendsTheContractBodyAndThenTheImages() async throws {
        let http = FakeHTTP()
        http.answers["POST /v1/support/tickets"] = (201, #"{"ticket_id":"tkt_0123456789abcdef","status":"waiting","created_at":1}"#)
        http.answers["POST /v1/support/tickets/tkt_0123456789abcdef/attachments"] = (201, #"{"id":"att_0123456789abcdef","content_type":"image/jpeg","bytes":3,"at":1}"#)
        let tokens = MemorySupportTokenStore()
        let transport = stack(http).supportTransport(uid: { "user-1" }, tokens: tokens)
        #expect(transport.capabilities == SupportCapabilities(replies: true, images: true))

        let id = try await transport.submit(SupportRequest(category: .billing, subject: "  ", body: " 解約したい \n", email: "",
                                                           images: [SupportImage(data: Data([1, 2, 3]), contentType: "image/jpeg")]),
                                            context: context(), lang: "ja")
        #expect(id == "tkt_0123456789abcdef")

        let first = http.requests[0]
        #expect(first.url?.absoluteString == "https://api.appgrowstack.com/v1/support/tickets")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer pk_KUdMabcdefghijklmnopqrst")
        #expect(first.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/3.2.0/swift-app-support/\(SupportSDK.version)")
        #expect(first.value(forHTTPHeaderField: "X-Support-Token") == nil)
        let body = try http.json(0)
        #expect(Set(body.keys) == ["install_id", "uid", "owner_token", "lang", "category", "body", "context"])
        #expect(body["install_id"] as? String == "a1b2c3d4-0000-4000-8000-000000000001")
        #expect(body["body"] as? String == "解約したい")
        let token = try #require(body["owner_token"] as? String)
        #expect(token.count >= 32 && token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(tokens.load() == token)
        let ctx = try #require(body["context"] as? [String: Any])
        #expect(ctx["session_id"] as? String == "ses_0123456789abcdef")

        let upload = http.requests[1]
        #expect(upload.url?.path() == "/v1/support/tickets/tkt_0123456789abcdef/attachments")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(upload.value(forHTTPHeaderField: "X-Support-Token") == token)
        #expect(upload.httpBody == Data([1, 2, 3]))
    }

    @Test func sendFeedbackSendsTheContractBodyWithoutAToken() async throws {
        let http = FakeHTTP()
        http.answers["POST /v1/support/feedback"] = (201, #"{"feedback_id":"fbk_0123456789abcdef","created_at":1}"#)
        let tokens = MemorySupportTokenStore()
        let transport = stack(http).supportTransport(uid: { nil }, tokens: tokens)

        let id = try await transport.sendFeedback(" 値段がもう少し安ければ \n", campaign: "survey-why-not-premium", choice: "choice_1",
                                                  context: context(), lang: "ja")
        #expect(id == "fbk_0123456789abcdef")
        let request = http.requests[0]
        #expect(request.url?.absoluteString == "https://api.appgrowstack.com/v1/support/feedback")
        #expect(request.value(forHTTPHeaderField: "X-Support-Token") == nil)
        let body = try http.json(0)
        #expect(Set(body.keys) == ["install_id", "lang", "campaign", "choice", "text", "context"])
        #expect(body["text"] as? String == "値段がもう少し安ければ")
        #expect(body["choice"] as? String == "choice_1")
        #expect(tokens.load() == nil)

        // From settings: no campaign, so no choice either. Nothing written: nothing sent.
        _ = try await transport.sendFeedback("同期が欲しい", choice: "choice_2", context: context(), lang: "ja")
        #expect(Set(try http.json(1).keys) == ["install_id", "lang", "text", "context"])
        #expect(try await transport.sendFeedback("  \n", context: context(), lang: "ja") == nil)
        #expect(http.requests.count == 2)

        http.answers["POST /v1/support/feedback"] = (429, #"{"error":{"code":"rate_limited","message":"1時間に5件まで"}}"#)
        await #expect(throws: SupportError.rateLimited) { try await transport.sendFeedback("x", context: context(), lang: "ja") }
    }

    @Test func ticketsAreEmptyWithoutATokenAndReadWithIt() async throws {
        let http = FakeHTTP()
        http.answers["GET /v1/support/tickets"] = (200, ticketJSON)
        let tokens = MemorySupportTokenStore()
        let transport = stack(http).supportTransport(tokens: tokens)
        #expect(try await transport.tickets().isEmpty)
        #expect(http.requests.isEmpty)

        tokens.save(String(repeating: "t", count: 40))
        let tickets = try await transport.tickets()
        #expect(http.requests[0].value(forHTTPHeaderField: "X-Support-Token") == String(repeating: "t", count: 40))
        #expect(tickets.first?.status == .answered)
        #expect(tickets.first?.latestReply?.body == "App Store で解約できます")
    }

    @Test func errorsAreTyped() async throws {
        let http = FakeHTTP()
        http.answers["POST /v1/support/tickets"] = (429, #"{"error":{"code":"rate_limited","message":"x"}}"#)
        http.answers["POST /v1/support/tickets/tkt_ffffffffffffffff/messages"] = (404, #"{"error":{"code":"not_found","message":"x"}}"#)
        http.answers["GET /v1/support/articles"] = (400, #"{"error":{"code":"invalid","message":"lang"}}"#)
        let transport = stack(http).supportTransport(tokens: MemorySupportTokenStore())
        await #expect(throws: SupportError.rateLimited) { try await transport.submit(SupportRequest(category: .bug, body: "x"), context: context(), lang: "ja") }
        await #expect(throws: SupportError.notFound) { try await transport.reply("x", to: "tkt_ffffffffffffffff") }
        await #expect(throws: SupportError.rejected(status: 400, code: "invalid", message: "lang")) { try await transport.articles(lang: "ja") }
        await #expect(throws: SupportError.self) { try await transport.uploadImage(SupportImage(data: Data(), contentType: "image/png"), ticketID: "tkt_x") }
    }

    @Test func articlesAskForTheLanguageOnTheStacksEnvironment() async throws {
        let http = FakeHTTP()
        http.answers["GET /v1/support/articles"] = (200, articlesJSON)
        let articles = try await stack(http, environment: .staging).supportTransport(tokens: MemorySupportTokenStore()).articles(lang: "zh-Hant")
        #expect(http.requests[0].url?.absoluteString == "https://api-staging.appgrowstack.com/v1/support/articles?lang=zh-Hant")
        #expect(articles.map(\.slug) == ["cancel-subscription"])
    }

    @Test @MainActor func theContextCarriesTheStacksActivity() throws {
        let s = stack(FakeHTTP())
        s.activity.record(AppGrowStackActivity.Event(name: "habit_achieved", at: Date(timeIntervalSince1970: 1_700_000_000), props: ["streak_days": .int(3)]))
        s.activity.record(AppGrowStackActivity.ShownCampaign(campaign: "trial-offer", setVersion: 3, at: Date(timeIntervalSince1970: 1_700_000_000)))
        let make = s.supportContext(isPremium: { true }, sessionID: { "ses_0123456789abcdef" })
        let ctx = make("paywall")
        #expect(ctx.channel == .appStore)
        #expect(ctx.isPremium == true)
        #expect(ctx.sessionID == "ses_0123456789abcdef")
        #expect(ctx.screen == "paywall")
        #expect(ctx.recentEvents == [SupportRecentEvent(name: "habit_achieved", at: Date(timeIntervalSince1970: 1_700_000_000), props: ["streak_days": .int(3)])])
        #expect(ctx.campaignsShown == [SupportCampaignShown(campaign: "trial-offer", setVersion: 3, at: Date(timeIntervalSince1970: 1_700_000_000))])
    }

    @Test @MainActor func theCenterUsesTheTransportsArticles() async {
        let http = FakeHTTP()
        http.answers["GET /v1/support/articles"] = (200, articlesJSON)
        let s = stack(http)
        let center = SupportCenter(transport: s.supportTransport(tokens: MemorySupportTokenStore()), lang: "ja", context: s.supportContext())
        await center.refresh()
        #expect(center.articles.count == 1)
        #expect(center.capabilities.replies)
    }
}
#endif
