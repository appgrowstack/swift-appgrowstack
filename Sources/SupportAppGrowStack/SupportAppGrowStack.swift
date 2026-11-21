#if Support
import AppGrowStackCore
import Foundation
import Security
import SupportCore

/// Keeps the owner token: the random key that lets this install read its own requests and replies.
/// The server stores only its SHA-256.
public protocol SupportTokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
}

/// The owner token in the Keychain (this device only, readable after the first unlock).
public struct KeychainSupportTokenStore: SupportTokenStore {
    public let service: String
    public let account: String

    public init(service: String = "swift-app-support", account: String = "owner_token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// An in-memory store for tests and previews.
public final class MemorySupportTokenStore: SupportTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) { self.token = token }

    public func load() -> String? { lock.withLock { token } }
    public func save(_ token: String) { lock.withLock { self.token = token } }
}

/// Support on appgrowstack (`/v1/support/*`): requests with screenshots, the install's own requests
/// and replies (read with the owner token), and the product's help articles.
public struct AppGrowStackSupportTransport: SupportTransport, HelpArticleSource {
    let stack: AppGrowStack
    let uid: @Sendable () -> String?
    let tokens: any SupportTokenStore

    public var capabilities: SupportCapabilities { SupportCapabilities(replies: true, images: true) }

    /// The owner token, made on first use (43 URL-safe characters from 32 random bytes).
    public func ownerToken() -> String {
        if let t = tokens.load(), t.count >= 32 { return t }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        tokens.save(token)
        return token
    }

    /// Whether this install has ever sent a request (and so may have replies to read).
    public var hasOwnerToken: Bool { (tokens.load()?.count ?? 0) >= 32 }

    /// Makes the request, then sends its images one by one. Throws only when the request was not
    /// made; an image that fails after that comes back in ``SupportSubmission/unsentImages`` (sending
    /// the whole form again would make a second request).
    public func submit(_ request: SupportRequest, context: SupportContext, lang: String) async throws -> SupportSubmission {
        struct Body: Encodable {
            let install_id: String
            let uid: String?
            let owner_token: String
            let lang: String
            let email: String?
            let category: SupportCategory
            let subject: String?
            let body: String
            let context: SupportContext
        }
        struct Created: Decodable { let ticket_id: String }
        let subject = request.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = request.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(
            install_id: stack.installID,
            uid: uid(),
            owner_token: ownerToken(),
            lang: lang,
            email: email?.isEmpty == false ? email : nil,
            category: request.category,
            subject: subject?.isEmpty == false ? String(subject!.prefix(120)) : nil,
            body: String(request.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)),
            context: context
        )
        let created: Created = try await call("POST", "/v1/support/tickets", json: body, token: false)
        var unsent: [SupportImage] = []
        for image in request.images.prefix(4) {
            do {
                _ = try await uploadImage(image, ticketID: created.ticket_id)
            } catch {
                unsent.append(image)
            }
        }
        return SupportSubmission(ticketID: created.ticket_id, unsentImages: unsent)
    }

    public func tickets() async throws -> [SupportTicket] {
        guard hasOwnerToken else { return [] }
        struct List: Decodable { let tickets: [SupportTicket] }
        let list: List = try await decode(request("GET", "/v1/support/tickets", token: true))
        return list.tickets
    }

    public func reply(_ body: String, to ticketID: String) async throws -> SupportMessage {
        struct Body: Encodable { let body: String }
        return try await call("POST", "/v1/support/tickets/\(ticketID)/messages", json: Body(body: String(body.prefix(4000))), token: true)
    }

    public func uploadImage(_ image: SupportImage, ticketID: String) async throws -> SupportAttachment {
        var req = request("POST", "/v1/support/tickets/\(ticketID)/attachments", token: true)
        req.setValue(image.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = image.data
        return try await decode(req)
    }

    public func articles(lang: String) async throws -> [HelpArticle] {
        struct List: Decodable { let articles: [HelpArticle] }
        let list: List = try await decode(stack.request("GET", "/v1/support/articles", query: [URLQueryItem(name: "lang", value: lang)],
                                                                    sdk: SupportSDK.name, version: SupportSDK.version))
        return list.articles
    }

    /// Sends what a person wrote: in a survey (`campaign` and the `choice` they picked, the id the
    /// sheet handed `CampaignEngine.answer`), or from a "send feedback" screen in settings (both `nil`).
    /// No reply comes back; the words are sorted into topics on the server. Empty text is not sent.
    /// - Returns: the feedback id, or `nil` when there was nothing to send.
    @discardableResult
    public func sendFeedback(_ text: String, campaign: String? = nil, choice: String? = nil,
                             context: SupportContext, lang: String) async throws -> String? {
        struct Body: Encodable {
            let install_id: String
            let uid: String?
            let lang: String
            let campaign: String?
            let choice: String?
            let text: String
            let context: SupportContext
        }
        struct Created: Decodable { let feedback_id: String }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let body = Body(
            install_id: stack.installID,
            uid: uid(),
            lang: lang,
            campaign: campaign,
            // A choice belongs to a survey; without the campaign the server would refuse it.
            choice: campaign == nil ? nil : choice,
            text: String(trimmed.prefix(2000)),
            context: context
        )
        let created: Created = try await call("POST", "/v1/support/feedback", json: body, token: false)
        return created.feedback_id
    }

    // MARK: - HTTP

    private func request(_ method: String, _ path: String, token: Bool) -> URLRequest {
        var req = stack.request(method, path, sdk: SupportSDK.name, version: SupportSDK.version)
        if token { req.setValue(ownerToken(), forHTTPHeaderField: "X-Support-Token") }
        return req
    }

    private func call<T: Decodable, B: Encodable>(_ method: String, _ path: String, json: B, token: Bool) async throws -> T {
        var req = request(method, path, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(json)
        return try await decode(req)
    }

    private func decode<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await stack.send(req)
        } catch {
            throw SupportError.transport(error.localizedDescription)
        }
        switch response.statusCode {
        case 200 ..< 300:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw SupportError.transport("unreadable answer: \(error)") }
        case 404: throw SupportError.notFound
        case 429: throw SupportError.rateLimited
        default:
            let e = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw SupportError.rejected(status: response.statusCode, code: e?.error.code ?? "unknown", message: e?.error.message ?? "")
        }
    }
}

/// `{ "error": { "code", "message" } }`
private struct ErrorBody: Decodable {
    struct Inner: Decodable {
        let code: String
        let message: String
    }
    let error: Inner
}

extension AppGrowStack {
    /// The transport for `SupportCenter(transport:)`. It is also the article source.
    /// - Parameter uid: the signed-in account, if any. Read at each request.
    public func supportTransport(
        uid: @escaping @Sendable () -> String? = { nil },
        tokens: any SupportTokenStore = KeychainSupportTokenStore()
    ) -> AppGrowStackSupportTransport {
        AppGrowStackSupportTransport(stack: self, uid: uid, tokens: tokens)
    }

    /// The context for `SupportCenter(context:)`: this device and build, plus the stack's recent
    /// events and campaigns shown (written by the analytics and campaign connectors).
    public func supportContext(
        isPremium: @escaping @MainActor () -> Bool? = { nil },
        sessionID: @escaping @MainActor () -> String? = { nil },
        bundle: Bundle = .main
    ) -> @MainActor (_ screen: String?) -> SupportContext {
        let channel = SupportContext.Channel(rawValue: app.channel.rawValue) ?? .debug
        let activity = activity
        return { screen in
            SupportContext.current(
                channel: channel,
                isPremium: isPremium(),
                sessionID: sessionID(),
                screen: screen,
                recentEvents: activity.events.map { event in
                    SupportRecentEvent(name: event.name, at: event.at, props: event.props.mapValues(SupportValue.init))
                },
                campaignsShown: activity.campaigns.map { SupportCampaignShown(campaign: $0.campaign, setVersion: $0.setVersion, at: $0.at) },
                bundle: bundle
            )
        }
    }
}

extension SupportValue {
    init(_ value: AppGrowStackActivity.Value) {
        switch value {
        case .string(let v): self = .string(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .bool(let v): self = .bool(v)
        }
    }
}
#endif
