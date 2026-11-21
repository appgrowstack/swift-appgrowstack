# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-22

### Added

- `SupportAppGrowStack`: `AppGrowStackSupportTransport.sendFeedback(_:campaign:choice:context:lang:)`
  sends what a person wrote in a survey (or from settings) to `POST /v1/support/feedback`.
- `CampaignAppGrowStack`: `stack.campaignContext`, the engine's context from the stack's values with
  the first-seen date.
- `ConfigAppGrowStack` (trait `Config`, swift-app-config 0.1): `stack.configSource(fallback:)` fetches
  the config set with `GET /v1/config/sets/<public key>` (ETag, 304, the `AppGrowStack-Client` header
  naming swift-app-config); `stack.configContext` gives the device values for rules.

### Changed

- Needs swift-app-campaign 0.4, swift-app-support 0.3 and swift-app-sessions 0.1.1.

### Fixed

- `SessionsAppGrowStack` sends each batch with `AppGrowStack.installID` as its `install_id`, so the light
  record joins the same install as the analytics, links and support. It sent the id the recorder kept.

## [0.1.0] - 2026-11-21

### Added

- `AppGrowStackCore`: `AppGrowStack`, the one value the connectors read (public key, environment,
  lowercase install id, first-seen date, recent activity) and `request(_:_:query:sdk:version:)`,
  whose `AppGrowStack-Client` header names the SDK the connector serves and its version, from that
  SDK's constants (`ios/3.4.0/swift-app-sessions/0.1.0`), never this package.
- Connector targets are added per SDK behind a trait of the same name, so an app fetches only the
  SDKs it enables.
- `LinksAppGrowStack` (trait `Links`, swift-app-links 0.2): `stack.attributionResolver()` decides the
  install's source with `POST /v1/links/attributions`.
- `SupportAppGrowStack` (trait `Support`, swift-app-support 0.2): `stack.supportTransport()` (requests,
  screenshots, replies with the owner token in the Keychain, help articles on `/v1/support/*`) and
  `stack.supportContext()` (the context with the stack's recent activity).
- `CampaignAppGrowStack` (trait `Campaign`, swift-app-campaign 0.3): `stack.campaignSource(fallback:)`
  fetches the set with `GET /v1/campaigns/sets/<public key>` (ETag, 304, the `AppGrowStack-Client`
  header naming swift-app-campaign) and uses the bundled set until the first fetch succeeds.
- `NotificationsAppGrowStack` (trait `Notifications`, swift-app-notifications 0.2):
  `stack.notificationOpenReporter()` reports an opened delivery with `POST /v1/notify/opened`. 429,
  5xx and a failed connection throw; other answers count as done.
- `SessionsAppGrowStack` (trait `Sessions`, swift-app-sessions 0.1): `stack.sessionSink()` sends the
  light record's batches with `POST /v1/sessions/batches`. 200 is accepted with the replay decision
  and the policy's kept properties, 204 is disabled, other 4xx drop the batch, 429, 5xx and a failed
  connection throw so the batch is sent again later.
