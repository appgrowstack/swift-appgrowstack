#if Links
import AppGrowStackCore
import AppLinks
import Foundation

/// Decides the install's source on appgrowstack (`POST /v1/links/attributions`). The server also
/// knows the short links' own sources and records `attribution_recorded` for the person.
///
/// The status is read with ``AppGrowStackAnswer``: 200 is decided, a body that will never pass
/// (400 and the other 4xx but 401, 403, 408 and 429) is rejected, and the rest (503 while Apple Ads
/// has not answered the server, 401 and 403, 429, 5xx, no connection) is tried on a later launch, up
/// to the reporter's `maxAttempts`.
public struct AppGrowStackAttributionResolver: AttributionResolving {
    let stack: AppGrowStack

    public func resolve(_ request: AttributionRequest) async -> AttributionResolution {
        var http = stack.request("POST", "/v1/links/attributions", sdk: AppLinksSDK.name, version: AppLinksSDK.version)
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = request
        body.installID = stack.installID
        guard let encoded = try? JSONEncoder().encode(body) else { return .rejected }
        http.httpBody = encoded
        guard let (data, response) = try? await stack.send(http) else { return .retryLater }
        switch AppGrowStackAnswer(status: response.statusCode) {
        case .accepted:
            guard let answer = try? JSONDecoder().decode(Attribution.self, from: data) else { return .retryLater }
            return .decided(answer)
        case .rejected:
            return .rejected
        case .retryLater:
            return .retryLater
        }
    }
}

extension AppGrowStack {
    /// The resolver for `AttributionReporter(resolver:)`. The install id is the stack's.
    public func attributionResolver() -> AppGrowStackAttributionResolver {
        AppGrowStackAttributionResolver(stack: self)
    }
}
#endif
