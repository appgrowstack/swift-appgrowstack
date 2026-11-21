#if Campaign
import AppGrowStackCore
import CampaignCore
import Foundation

/// The set from appgrowstack: `GET /v1/campaigns/sets/<public key>` with `If-None-Match` (ETag
/// `"v<version>"`). Stopping, holdouts and templates are in the set, so they work as soon as it
/// arrives. Until the first fetch succeeds, `fallback` (the set shipped in the app) is used.
///
/// The `AppGrowStack-Client` header names swift-app-campaign and its version
/// (`ios/3.3.0/swift-app-campaign/0.3.0`), so the server counts which versions fetch.
public struct AppGrowStackCampaignSetFetcher: CampaignSetFetching {
    let stack: AppGrowStack
    let fallback: (any CampaignSetFetching)?

    public func fetch(etag: String?) async throws -> CampaignFetchResult {
        do {
            return try await fromServer(etag: etag)
        } catch {
            // Never fetched (no ETag): the bundled set lets the first launch decide offline.
            guard etag == nil, let fallback else { throw error }
            return try await fallback.fetch(etag: nil)
        }
    }

    private func fromServer(etag: String?) async throws -> CampaignFetchResult {
        var request = stack.request("GET", "/v1/campaigns/sets/\(stack.publicKey)")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        // The key is in the path (auth "public_key_path"); the set is the same for everyone.
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue("\(stack.app.platform)/\(stack.app.version)/\(CampaignSDK.name)/\(CampaignSDK.version)",
                         forHTTPHeaderField: "AppGrowStack-Client")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await stack.send(request)
        switch response.statusCode {
        case 200: return .fetched(data, etag: response.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        default: throw CampaignSetFetchFailure(status: response.statusCode)
        }
    }
}

extension AppGrowStack {
    /// The fetcher for `CampaignEngine(fetcher:)`.
    /// - Parameter fallback: the set shipped in the app (`BundledCampaignSetFetcher(resource: "campaigns")`),
    ///   used only until the first fetch succeeds.
    public func campaignSource(fallback: (any CampaignSetFetching)? = nil) -> AppGrowStackCampaignSetFetcher {
        AppGrowStackCampaignSetFetcher(stack: self, fallback: fallback)
    }
}
#endif
