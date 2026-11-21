import Foundation

/// The one value that connects the app-* SDKs to appgrowstack.
///
/// Give it the public key, the environment and the install id once; every connector
/// (`CampaignAppGrowStack`, `LinksAppGrowStack`, …) reads them from here, so the key, the root URL
/// and the install id are never passed to an SDK one by one. The engines themselves (campaigns,
/// support, attribution) are still built by the app: placements, actions and screens are the app's.
///
/// ```swift
/// let stack = AppGrowStack(
///     publicKey: "pk_…",
///     environment: .production,
///     installID: InstallID.current,
///     firstSeenAt: legacyFirstOpenDate,
///     app: .current(channel: .appStore)
/// )
/// ```
public final class AppGrowStack: Sendable {
    public let publicKey: String
    public let environment: AppGrowStackEnvironment
    /// Always lowercase (the contract's form), whatever case the app passed.
    public let installID: String
    public let app: AppGrowStackApp
    /// The earlier of the date passed at init and the date stored from an earlier launch.
    public let firstSeenAt: Date
    /// Recent events and campaigns shown, written by the analytics and campaign connectors and read
    /// by the support connector.
    public let activity: AppGrowStackActivity
    public let isInternalDevice: @Sendable () -> Bool
    let http: any AppGrowStackHTTP

    /// - Parameters:
    ///   - installID: the id the app's analytics uses for this install. Any case; it is lowercased.
    ///   - firstSeenAt: when the person first used the app, if the app knew it before this value
    ///     existed. The earlier of this and the stored date is kept.
    ///   - storage: where the first-seen date is kept between launches.
    ///   - http: sends the connectors' requests. `URLSession.shared` by default; tests pass a fake.
    public init(
        publicKey: String,
        environment: AppGrowStackEnvironment = .production,
        installID: String,
        firstSeenAt: Date? = nil,
        app: AppGrowStackApp,
        isInternalDevice: @escaping @Sendable () -> Bool = { false },
        storage: any AppGrowStackStorage = UserDefaultsAppGrowStackStorage(),
        http: any AppGrowStackHTTP = URLSessionAppGrowStackHTTP(),
        now: () -> Date = Date.init
    ) {
        self.publicKey = publicKey
        self.environment = environment
        self.installID = installID.lowercased()
        self.app = app
        self.isInternalDevice = isInternalDevice
        self.http = http
        self.activity = AppGrowStackActivity()
        let stored = storage.firstSeenAt
        let earliest = [stored, firstSeenAt, stored == nil && firstSeenAt == nil ? now() : nil].compactMap { $0 }.min()!
        if stored != earliest { storage.firstSeenAt = earliest }
        self.firstSeenAt = earliest
    }

    /// The id of the person the connectors report for. The install id until people are resolved on
    /// the server (`POST /v1/people/resolve`, not in the contract yet).
    public var person: @Sendable () -> String {
        let id = installID
        return { id }
    }

    /// `AppGrowStack-Client: <platform>/<app version>/<sdk>/<sdk version>` (contracts K2-5).
    ///
    /// `sdk` and `version` are the SDK the connector serves (`CampaignSDK.name`, `SessionsSDK.version`,
    /// …), not this package, so the server counts which versions of that SDK call.
    public func clientHeader(sdk: String, version: String) -> String {
        "\(app.platform)/\(app.version)/\(sdk)/\(version)"
    }

    /// A request to `path` under the environment's root, with the public key and the client header
    /// naming `sdk` at `version` (``clientHeader(sdk:version:)``).
    public func request(_ method: String, _ path: String, query: [URLQueryItem] = [], sdk: String, version: String) -> URLRequest {
        var components = URLComponents(url: environment.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(publicKey)", forHTTPHeaderField: "Authorization")
        request.setValue(clientHeader(sdk: sdk, version: version), forHTTPHeaderField: "AppGrowStack-Client")
        return request
    }

    /// Sends a request built with ``request(_:_:query:sdk:version:)``.
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await http.send(request)
    }
}

/// Which appgrowstack the connectors talk to. Only the root URL; each connector adds its path.
public enum AppGrowStackEnvironment: Sendable, Hashable {
    case production
    case staging
    /// A stack on this machine (`scripts/dev-stack.sh`), e.g. `http://127.0.0.1:8787`.
    case local(URL)

    public var baseURL: URL {
        switch self {
        case .production: URL(string: "https://api.appgrowstack.com")!
        case .staging: URL(string: "https://api-staging.appgrowstack.com")!
        case .local(let url): url
        }
    }
}

/// The build the connectors describe.
public struct AppGrowStackApp: Sendable, Hashable {
    /// Where the build came from (the contract's `buildChannel`).
    public enum Channel: String, Sendable, Hashable {
        case appStore = "appstore"
        case testFlight = "testflight"
        case debug
    }

    public var platform: String
    /// `x.y.z` (or `x.y`).
    public var version: String
    public var build: String
    public var channel: Channel
    public var lang: String
    public var region: String?

    public init(platform: String = "ios", version: String, build: String, channel: Channel, lang: String, region: String? = nil) {
        self.platform = platform
        self.version = version
        self.build = build
        self.channel = channel
        self.lang = lang
        self.region = region
    }

    /// The running build: version and build from the bundle, language and region from the locale.
    public static func current(channel: Channel, bundle: Bundle = .main, locale: Locale = .current) -> AppGrowStackApp {
        let info = bundle.infoDictionary ?? [:]
        return AppGrowStackApp(
            version: normalizedVersion(info["CFBundleShortVersionString"] as? String ?? "0.0"),
            build: String((info["CFBundleVersion"] as? String ?? "0").prefix(32)),
            channel: channel,
            lang: bundle.preferredLocalizations.first ?? locale.language.languageCode?.identifier ?? "en",
            region: locale.region?.identifier
        )
    }

    /// `3.2` stays `3.2`, `3.2.0.1` becomes `3.2.0`, anything else becomes `0.0`.
    static func normalizedVersion(_ raw: String) -> String {
        let parts = raw.split(separator: ".").prefix(3)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return "0.0" }
        return parts.joined(separator: ".")
    }
}

/// What `AppGrowStack` keeps between launches.
public protocol AppGrowStackStorage: Sendable {
    var firstSeenAt: Date? { get nonmutating set }
}

/// `UserDefaults` under `appgrowstack.*`.
public struct UserDefaultsAppGrowStackStorage: AppGrowStackStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var firstSeenAt: Date? {
        get { (defaults.object(forKey: "appgrowstack.first_seen_at") as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        nonmutating set { defaults.set(newValue.map { NSNumber(value: $0.timeIntervalSince1970) }, forKey: "appgrowstack.first_seen_at") }
    }
}

/// An in-memory store for tests and previews.
public final class MemoryAppGrowStackStorage: AppGrowStackStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date?

    public init(firstSeenAt: Date? = nil) { stored = firstSeenAt }

    public var firstSeenAt: Date? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Sends the connectors' requests.
public protocol AppGrowStackHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAppGrowStackHTTP: AppGrowStackHTTP {
    public let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
