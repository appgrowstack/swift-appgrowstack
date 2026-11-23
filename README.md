# swift-appgrowstack

Connect the swift-app-* packages to appgrowstack, enabling only the connectors of the packages you use.

[Japanese](./README.ja.md)

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

Each swift-app-* package works on its own. This package adds the parts that talk to the
appgrowstack server: one `AppGrowStack` value, and one connector product per package.

## Features

- **One value to connect.** `AppGrowStack` takes the public key, the environment and the install id
  once. Every connector reads them from it, so no package is handed a key or a URL
- **One connector per package, behind a trait.** A connector depends on its package only when the
  trait of the same name is enabled, so SwiftPM fetches only the packages you use
- **Shared context.** The install id is lowercased in one place, the first-seen date is the earliest
  one known (kept in `UserDefaults` by default), and recent events and campaigns shown are kept in
  `stack.activity` for the support connector
- **Environments.** `.production`, `.staging` and `.local(URL)`. Every request carries the public key
  and the `AppGrowStack-Client` header
- **The owner's own devices.** Every request also carries `AppGrowStack-Device` (`stack.deviceHash`)
  and `AppGrowStack-Install` (the install id), so appgrowstack can count only real users and keep the
  owner's own devices out of the numbers. The device id is a random id made once and kept in the
  Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced to iCloud), so it stays the
  same when the app is deleted and installed again and when a new account is made. Only
  `sha256(public key + ":" + device id)` is sent; the raw id never leaves the device. The owner marks a
  device once by opening the owner link from the appgrowstack console on that device and then opening
  the app on the same network. If the Keychain cannot be used, the id is kept in `UserDefaults` (it then
  changes on reinstall). Tests pass `deviceStore: MemoryAppGrowStackDeviceStore()`
- **One answer table.** `AppGrowStackAnswer` reads every status the same way in every connector:
  2xx is done, 401, 403, 408, 429 and 5xx are sent again later, and any other 4xx is dropped

### Connectors

| Product | Trait | Package | What it adds |
|---|---|---|---|
| `AppGrowStackCore` | none | none | `AppGrowStack`, `AppGrowStackApp`, `AppGrowStackEnvironment` |
| `LinksAppGrowStack` | `Links` | swift-app-links | `stack.attributionResolver()`: the install's source decided on the server (`POST /v1/links/attributions`) |
| `SupportAppGrowStack` | `Support` | swift-app-support | `stack.supportTransport(uid:tokens:)`: requests with screenshots, the install's own requests and replies (owner token in the Keychain) and help articles on the server. `stack.supportContext(isPremium:sessionID:)`: the context with the stack's recent events and campaigns shown |
| `CampaignAppGrowStack` | `Campaign` | swift-app-campaign | `stack.campaignSource(fallback:)`: the set fetched from the server (ETag, 304), the bundled set until the first fetch succeeds |
| `NotificationsAppGrowStack` | `Notifications` | swift-app-notifications | `stack.notificationOpenReporter()`: tells the server a delivery was opened (`POST /v1/notify/opened`). Hand `report(sendID:)` to `NotificationCenterDelegate(reportOpened:)` |
| `SessionsAppGrowStack` | `Sessions` | swift-app-sessions | `stack.sessionSink()`: the `SessionSink` that sends the light record's batches (`POST /v1/sessions/batches`) and hands back the server's replay decision, kept properties, upload token and live offer. `stack.sessionReplaySink()`: the recording's segments (`PUT /v1/sessions/:session_id/segments/:seq`). `stack.sessionLiveConnector()`: the live view's WebSocket |
| `ConfigAppGrowStack` | `Config` | swift-app-config | `stack.configSource(fallback:)` and `stack.configContext`: the config set fetched from the server (ETag, 304), the bundled set until the first fetch succeeds |

## Quick Start

```swift
import AppGrowStackCore
import AppLinks
import LinksAppGrowStack

let stack = AppGrowStack(
    publicKey: "pk_…",
    environment: .production,
    installID: installID,                 // the id your analytics uses for this install
    app: .current(channel: .appStore)
)

@MainActor let attribution = AttributionReporter(
    installID: stack.installID,
    appVersion: stack.app.version,
    resolver: stack.attributionResolver(),
    firstOpenAt: stack.firstSeenAt
)
```

### Other connectors

```swift
import SupportAppGrowStack
import SupportCore

@MainActor let support = SupportCenter(
    transport: stack.supportTransport(uid: { auth.uid }),
    lang: stack.app.lang,
    context: stack.supportContext(isPremium: { premium.isPremium })
)
```

```swift
import CampaignAppGrowStack
import CampaignCore

let campaigns = CampaignEngine(
    fetcher: stack.campaignSource(fallback: BundledCampaignSetFetcher(resource: "campaigns")),
    context: campaignContext,
    person: stack.person,
    isInternalDevice: stack.isInternalDevice,
    placements: [CampaignTemplate.TrialOffer.self],
    record: { event in analytics.track(event.name, event.parameters) }
)
```

## Documentation

The API reference is the symbol documentation in `Sources`. Open it in Xcode with
Product > Build Documentation. Changes are listed in [CHANGELOG.md](./CHANGELOG.md).

## Installation

Add the package and enable a trait for each package you use:

```swift
.package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.6.0"), traits: ["Links", "Support", "Campaign"])
```

Then add the connector products to your target:

```swift
.product(name: "LinksAppGrowStack", package: "swift-appgrowstack"),
.product(name: "SupportAppGrowStack", package: "swift-appgrowstack"),
.product(name: "CampaignAppGrowStack", package: "swift-appgrowstack"),
```

The traits are `Links`, `Support`, `Campaign`, `Notifications`, `Sessions` and `Config`. None is enabled by
default.

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## License

MIT. See [LICENSE](./LICENSE).
