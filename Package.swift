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
/// .package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.1.0"), traits: ["Campaign"])
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
        .library(name: "LinksAppGrowStack", targets: ["LinksAppGrowStack"])
    ],
    traits: [
        .trait(name: "Links", description: "LinksAppGrowStack (swift-app-links)"),
        .default(enabledTraits: [])
    ],
    dependencies: [
        sdk("swift-app-links", from: "0.2.0")
    ],
    targets: [
        .target(name: "AppGrowStackCore"),
        .target(name: "LinksAppGrowStack", dependencies: [
            "AppGrowStackCore",
            .product(name: "AppLinks", package: "swift-app-links", condition: .when(traits: ["Links"]))
        ]),
        .testTarget(name: "AppGrowStackCoreTests", dependencies: ["AppGrowStackCore"]),
        .testTarget(name: "LinksAppGrowStackTests", dependencies: ["LinksAppGrowStack", "AppGrowStackCore"])
    ]
)
