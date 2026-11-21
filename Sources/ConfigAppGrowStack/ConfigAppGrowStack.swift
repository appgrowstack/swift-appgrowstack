#if Config
import AppGrowStackCore
import ConfigCore
import Foundation

/// The set from appgrowstack: `GET /v1/config/sets/<public key>` with `If-None-Match` (ETag
/// `"v<version>"`). The set is the same for everyone; rules and variants are decided on the device.
/// Until the first fetch succeeds, `fallback` (the set shipped in the app) is used.
///
/// The `AppGrowStack-Client` header names swift-app-config and its version
/// (`ios/2.4.0/swift-app-config/0.1.0`), so the server counts which versions fetch.
public struct AppGrowStackConfigSetSource: ConfigSetSource {
    let stack: AppGrowStack
    let fallback: (any ConfigSetSource)?

    public func fetch(etag: String?) async throws -> ConfigFetchResult {
        do {
            return try await fromServer(etag: etag)
        } catch {
            // Never fetched (no ETag): the bundled set is saved so the next launch has it offline.
            guard etag == nil, let fallback else { throw error }
            return try await fallback.fetch(etag: nil)
        }
    }

    private func fromServer(etag: String?) async throws -> ConfigFetchResult {
        var request = stack.request("GET", "/v1/config/sets/\(stack.publicKey)", sdk: ConfigSDK.name, version: ConfigSDK.version)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        // The key is in the path (auth "public_key_path"); the set is the same for everyone.
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await stack.send(request)
        switch response.statusCode {
        case 200: return .fetched(data, etag: response.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        default: throw ConfigSetFetchFailure(status: response.statusCode)
        }
    }
}

extension AppGrowStack {
    /// The source for `AppConfig(source:)`.
    /// - Parameter fallback: the set shipped in the app (`.bundled("config")`), used only until the
    ///   first fetch succeeds.
    public func configSource(fallback: (any ConfigSetSource)? = nil) -> AppGrowStackConfigSetSource {
        AppGrowStackConfigSetSource(stack: self, fallback: fallback)
    }

    /// The SDK's device values for `AppConfig(context:)`, from the stack's app and first-seen date.
    public var configContext: ConfigContext {
        ConfigContext(platform: app.platform, appVersion: app.version, build: app.build, channel: app.channel.rawValue,
                      lang: app.lang, region: app.region, firstSeenAt: firstSeenAt)
    }
}
#endif
