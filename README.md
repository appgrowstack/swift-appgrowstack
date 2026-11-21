# swift-appgrowstack

[Japanese](./README.ja.md)

Connects the app-* SDKs (swift-app-campaign, swift-app-links, swift-app-support, …) to
appgrowstack. Each SDK works on its own; this package adds the parts that talk to the server.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

> Developed in a private monorepo and copied here one way. Issues are welcome; pull requests are
> not accepted.

## Features

- **One value to connect.** `AppGrowStack` takes the public key, the environment and the install id
  once. Every connector reads them from it, so no SDK is handed a key or a URL
- **One connector per SDK, behind a trait.** Enable only the traits of the SDKs you use; SwiftPM
  then fetches only those SDKs
- **Shared context.** The install id is lowercased in one place, the first-seen date is the earliest
  one known, and recent events and campaigns shown are kept for the support connector

## Quick Start

```swift
import AppGrowStackCore

let stack = AppGrowStack(
    publicKey: "pk_…",
    environment: .production,
    installID: InstallID.current,
    app: .current(channel: .appStore)
)
```

## Connectors

| Product | Trait | SDK | What it adds |
|---|---|---|---|
| `LinksAppGrowStack` | `Links` | swift-app-links | `stack.attributionResolver()`: the install's source decided on the server (`POST /v1/links/attributions`), with the short links' own sources |

```swift
import LinksAppGrowStack

let attribution = AttributionReporter(installID: stack.installID, appVersion: stack.app.version, resolver: stack.attributionResolver())
```

## Installation

Add the package and enable a trait for each SDK you use.

```swift
.package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.1.0"), traits: ["Links"])
```

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.2+ (traits need SwiftPM 6.1+)

## License

MIT
