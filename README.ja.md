# swift-appgrowstack

app-*のSDK（swift-app-campaign・swift-app-links・swift-app-supportなど）をappgrowstackにつなぎます。SDKはどれも単体で動き、このパッケージはサーバーと話す所だけを足します。

[English](./README.md)

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

> 開発は非公開のモノリポでしていて、ここへは片方向にコピーするだけです。Issueは受けます。PRは受けません。

## 機能

- **つなぐ値は1つ。** `AppGrowStack`に公開キー・環境・install idを1回渡すと、全部のコネクタがそこから読みます。SDKにキーやURLを渡しません
- **コネクタはSDKごとに、traitの後ろに置く。** 使うSDKのtraitだけを有効にすると、SwiftPMはそのSDKだけを取りに行きます
- **共通の文脈。** install idの小文字への揃えは1か所で行い、初回の日付は知っている中で一番早い物にし、直近の出来事と出したキャンペーンを問い合わせのコネクタのために持ちます

## はじめに

```swift
import AppGrowStackCore

let stack = AppGrowStack(
    publicKey: "pk_…",
    environment: .production,
    installID: InstallID.current,
    app: .current(channel: .appStore)
)
```

## コネクタ

| product | trait | SDK | 足す物 |
|---|---|---|---|
| `LinksAppGrowStack` | `Links` | swift-app-links | `stack.attributionResolver()`：流入元をサーバーで決める（`POST /v1/links/attributions`）。短いリンクに書いた流入元も使う |
| `SupportAppGrowStack` | `Support` | swift-app-support | `stack.supportTransport()`：画像つきの問い合わせ・このinstallの問い合わせと返事（owner tokenはKeychain）・ヘルプの記事をサーバーで。`stack.supportContext()`：つなぐ型の直近の出来事と出したキャンペーンを入れた文脈 |

```swift
import LinksAppGrowStack

let attribution = AttributionReporter(installID: stack.installID, appVersion: stack.app.version, resolver: stack.attributionResolver())
```

```swift
import SupportAppGrowStack

let support = SupportCenter(transport: stack.supportTransport(uid: { auth.uid }), lang: "ja",
                            context: stack.supportContext(isPremium: { premium.isPremium }))
```

## 入れ方

パッケージを足し、使うSDKのtraitを有効にします。

```swift
.package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.1.0"), traits: ["Links"])
```

## 動く環境

- iOS 17+ / macOS 14+
- Swift 6.2+（traitsはSwiftPM 6.1から）

## ライセンス

MIT
