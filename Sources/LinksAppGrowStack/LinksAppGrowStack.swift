#if Links
import AppGrowStackCore
import AppLinks
import Foundation

/// Decides the install's source on appgrowstack (`POST /v1/links/attributions`). The server also
/// knows the short links' own sources and records `attribution_recorded` for the person.
public struct AppGrowStackAttributionResolver: AttributionResolving {
    let stack: AppGrowStack

    public func resolve(_ request: AttributionRequest) async -> AttributionResolution {
        var http = stack.request("POST", "/v1/links/attributions")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = request
        body.installID = stack.installID
        guard let encoded = try? JSONEncoder().encode(body) else { return .rejected }
        http.httpBody = encoded
        guard let (data, response) = try? await stack.send(http) else { return .retryLater }
        switch response.statusCode {
        case 200:
            guard let answer = try? JSONDecoder().decode(Attribution.self, from: data) else { return .retryLater }
            return .decided(answer)
        case 400:
            // The body will never pass; sending it again on every launch would only add noise.
            return .rejected
        default:
            // 503: Apple Ads has not answered the server yet. 429 and 5xx: later.
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
