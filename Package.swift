// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// Connects the app-* SDKs to appgrowstack: one `AppGrowStack` value (public key, environment,
/// install id, first-seen date, recent activity) and one connector target per SDK.
///
/// Each connector depends on its SDK only when the app enables that SDK's trait, so an app that uses
/// `CampaignAppGrowStack` alone never fetches swift-app-sessions:
///
/// ```swift
/// .package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.7.0"), traits: ["Campaign"])
/// ```
///
/// Inside the monorepo (`APPGROWSTACK_LOCAL` set) the SDKs are taken from the sibling folders.
let local = Context.environment["APPGROWSTACK_LOCAL"] != nil

/// An app-* SDK: the sibling folder in the monorepo, the published repository otherwise.
func sdk(_ name: String, from version: Version) -> Package.Dependency {
    local
        ? .package(path: "../\(name)")
        : .package(url: "https://github.com/appgrowstack/\(name).git", .upToNextMinor(from: version))
}

let package = Package(
    name: "swift-appgrowstack",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // The value every connector reads. Depends on no SDK.
        .library(name: "AppGrowStackCore", targets: ["AppGrowStackCore"]),
        // stack.attributionResolver(): the install's source decided on the server. Trait "Links".
        .library(name: "LinksAppGrowStack", targets: ["LinksAppGrowStack"]),
        // stack.supportTransport() and stack.supportContext(): requests, replies, screenshots and help
        // articles on the server, with the stack's recent activity attached. Trait "Support".
        .library(name: "SupportAppGrowStack", targets: ["SupportAppGrowStack"]),
        // stack.campaignSource(fallback:): the set fetched from the server (ETag, 304), the bundled
        // set until the first fetch. Trait "Campaign".
        .library(name: "CampaignAppGrowStack", targets: ["CampaignAppGrowStack"]),
        // stack.notificationOpenReporter(): tells the server a delivery was opened. Trait "Notifications".
        .library(name: "NotificationsAppGrowStack", targets: ["NotificationsAppGrowStack"]),
        // stack.sessionSink(): the light record's batches sent to the server. Trait "Sessions".
        .library(name: "SessionsAppGrowStack", targets: ["SessionsAppGrowStack"]),
        // stack.configSource(fallback:) and stack.configContext: the R9 set fetched from the server
        // (ETag, 304), the bundled set until the first fetch. Trait "Config".
        .library(name: "ConfigAppGrowStack", targets: ["ConfigAppGrowStack"])
    ],
    traits: [
        .trait(name: "Links", description: "LinksAppGrowStack (swift-app-links)"),
        .trait(name: "Support", description: "SupportAppGrowStack (swift-app-support)"),
        .trait(name: "Campaign", description: "CampaignAppGrowStack (swift-app-campaign)"),
        .trait(name: "Notifications", description: "NotificationsAppGrowStack (swift-app-notifications)"),
        .trait(name: "Sessions", description: "SessionsAppGrowStack (swift-app-sessions)"),
        .trait(name: "Config", description: "ConfigAppGrowStack (swift-app-config)"),
        .default(enabledTraits: [])
    ],
    dependencies: [
        sdk("swift-app-links", from: "0.3.0"),
        sdk("swift-app-support", from: "0.4.0"),
        sdk("swift-app-campaign", from: "0.7.0"),
        sdk("swift-app-notifications", from: "0.3.0"),
        sdk("swift-app-sessions", from: "0.3.0"),
        sdk("swift-app-config", from: "0.2.0")
    ],
    targets: [
        .target(name: "AppGrowStackCore"),
        .target(name: "LinksAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "AppLinks", package: "swift-app-links", condition: .when(traits: ["Links"]))
        ]),
        .target(name: "SupportAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "SupportCore", package: "swift-app-support", condition: .when(traits: ["Support"]))
        ]),
        .target(name: "CampaignAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "CampaignCore", package: "swift-app-campaign", condition: .when(traits: ["Campaign"]))
        ]),
        .target(name: "NotificationsAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "RemoteNotifications", package: "swift-app-notifications", condition: .when(traits: ["Notifications"]))
        ]),
        .target(name: "SessionsAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "SessionsCore", package: "swift-app-sessions", condition: .when(traits: ["Sessions"]))
        ]),
        .target(name: "ConfigAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "ConfigCore", package: "swift-app-config", condition: .when(traits: ["Config"]))
        ]),
        .testTarget(name: "AppGrowStackCoreTests", dependencies: ["AppGrowStackCore"]),
        .testTarget(name: "LinksAppGrowStackTests", dependencies: ["LinksAppGrowStack", "AppGrowStackCore"]),
        .testTarget(name: "SupportAppGrowStackTests", dependencies: ["SupportAppGrowStack", "AppGrowStackCore"]),
        .testTarget(name: "CampaignAppGrowStackTests", dependencies: ["CampaignAppGrowStack", "AppGrowStackCore"]),
        .testTarget(name: "NotificationsAppGrowStackTests", dependencies: ["NotificationsAppGrowStack", "AppGrowStackCore"]),
        .testTarget(name: "SessionsAppGrowStackTests", dependencies: [
            "SessionsAppGrowStack",
            "AppGrowStackCore",
            .product(name: "SessionsCore", package: "swift-app-sessions", condition: .when(traits: ["Sessions"]))
        ]),
        .testTarget(name: "ConfigAppGrowStackTests", dependencies: ["ConfigAppGrowStack", "AppGrowStackCore"])
    ]
)
