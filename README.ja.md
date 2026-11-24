# swift-appgrowstack

swift-app-*のパッケージをappgrowstackにつなぐ。使うパッケージのコネクターだけを有効にする。

[English](./README.md)

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

swift-app-*のパッケージはどれも単体で動きます。このパッケージはappgrowstackのサーバーとやり取りする所だけを足します。値の `AppGrowStack` が1つと、パッケージごとのコネクターのプロダクトです。

## 機能

- **つなぐ値は1つ。** `AppGrowStack` に公開キー・環境・install idを1回渡すと、どのコネクターもそこから読みます。パッケージにキーやURLを渡しません
- **コネクターはパッケージごとに、traitで分ける。** コネクターは同じ名前のtraitを有効にしたときだけ、そのパッケージに依存します。SwiftPMは使うパッケージだけを取りに行きます
- **共通の情報。** install idの小文字への揃えは1か所で行います。初回の日付は知っている中で一番早い物にします（指定しなければ `UserDefaults` に保存）。直近の出来事と出したキャンペーンは、問い合わせのコネクターのために `stack.activity` に持ちます
- **環境。** `.production`・`.staging`・`.local(URL)`。どのリクエストにも公開キーと `AppGrowStack-Client` のヘッダーを付けます
- **本人の端末。**どのリクエストにも`AppGrowStack-Device`（`stack.deviceHash`）と`AppGrowStack-Install`（install id）のヘッダーも付けます。appgrowstackはこれで本人の端末を数から外し、利用者だけを数えます。端末のidは最初に1回作る乱数で、キーチェーンに置きます（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`・iCloudに同期しない）。アプリを消して入れ直しても、アカウントを作り直しても変わりません。送るのは`sha256(公開キー+ ":" +端末のid)`だけで、端末のidそのものは端末の外に出ません。本人は、appgrowstackのconsoleの本人のリンクをその端末で開き、同じネットワークのままアプリを開いて、端末に1回だけマークを付けます。キーチェーンが使えないときは`UserDefaults`に置きます（そのときは入れ直すと変わります）。テストは`deviceStore: MemoryAppGrowStackDeviceStore()`を渡します
- **答えの読み方は1つの表。** `AppGrowStackAnswer` がどのコネクターでも同じに読みます。2xxは終わり、401・403・408・429・5xxは後で送り直し、ほかの4xxは捨てます

### コネクター

| プロダクト | trait | パッケージ | 足す物 |
|---|---|---|---|
| `AppGrowStackCore` | なし | なし | `AppGrowStack`・`AppGrowStackApp`・`AppGrowStackEnvironment` |
| `LinksAppGrowStack` | `Links` | swift-app-links | `stack.attributionResolver()`: インストールの流入元をサーバーで決める（`POST /v1/links/attributions`） |
| `SupportAppGrowStack` | `Support` | swift-app-support | `stack.supportTransport(uid:tokens:)`: スクリーンショット付きの問い合わせ・そのインストールの問い合わせと返事（オーナーのトークンはKeychain）・ヘルプの記事をサーバーで扱う。`stack.supportContext(isPremium:sessionID:)`: 直近の出来事と出したキャンペーンを含む情報 |
| `CampaignAppGrowStack` | `Campaign` | swift-app-campaign | `stack.campaignSource(fallback:)`: 組をサーバーから取る（ETag・304）。最初の取得が通るまでは同梱した組を使う |
| `NotificationsAppGrowStack` | `Notifications` | swift-app-notifications | `stack.notificationOpenReporter()`: 通知が開かれたことをサーバーに伝える（`POST /v1/notify/opened`）。`report(sendID:)` を `NotificationCenterDelegate(reportOpened:)` に渡す |
| `SessionsAppGrowStack` | `Sessions` | swift-app-sessions | `stack.sessionSink()`: 軽い記録のバッチを送る `SessionSink`（`POST /v1/sessions/batches`）。サーバーが決めた録画の要否・残すプロパティ・録画を送るためのトークン・ライブの依頼を返す。`stack.sessionReplaySink()`: 録画の塊を送る（`PUT /v1/sessions/:session_id/segments/:seq`）。`stack.sessionLiveConnector()`: ライブの WebSocket。`AppGrowStack.sessionEventProps(sessions)`: 計測の出来事に付ける `session_id` と `screen`（`AnalyticsBatchSink(extraProps:)` に渡す）。サーバーが出来事とセッションをつなぐ |
| `ConfigAppGrowStack` | `Config` | swift-app-config | `stack.configSource(fallback:)` と `stack.configContext`: 設定の組をサーバーから取る（ETag・304）。最初の取得が通るまでは同梱した組を使う |

## はじめに

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

### ほかのコネクター

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

## ドキュメント

APIの説明は `Sources` のシンボルのドキュメントです。
XcodeのProduct > Build Documentationで開けます。変更は [CHANGELOG.md](./CHANGELOG.md) にあります。

## 入れ方

パッケージを足し、使うパッケージごとにtraitを有効にします。

```swift
.package(url: "https://github.com/appgrowstack/swift-appgrowstack.git", .upToNextMinor(from: "0.6.0"), traits: ["Links", "Support", "Campaign"])
```

ターゲットにコネクターのプロダクトを足します。

```swift
.product(name: "LinksAppGrowStack", package: "swift-appgrowstack"),
.product(name: "SupportAppGrowStack", package: "swift-appgrowstack"),
.product(name: "CampaignAppGrowStack", package: "swift-appgrowstack"),
```

traitは `Links`・`Support`・`Campaign`・`Notifications`・`Sessions`・`Config` です。指定しなければ1つも有効になりません。

## 動く環境

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## ライセンス

MIT。[LICENSE](./LICENSE) を見てください。
