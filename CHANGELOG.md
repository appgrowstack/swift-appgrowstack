# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.7.0] - 2026-11-23

### Added

- `stack.sessionReplaySink()` (`AppGrowStackReplaySink`): the recording's segments to
  `PUT /v1/sessions/:session_id/segments/:seq` with `X-Session-Install` and `X-Session-Upload`. 403 and 404
  drop the session's segments, other 4xx drop the segment, 401, 408, 429 and 5xx keep it for later.
- `stack.sessionLiveConnector()` (`AppGrowStackLiveConnector`): the live view's WebSocket.

### Changed

- `stack.sessionSink()` reads `upload_token` and `live` from the batch answer.

## [0.6.0] - 2026-11-23

### Changed

- Depends on app-campaign 0.7.0 and app-sessions 0.2.0 (a person who already had what a `whats_new`
  campaign announces is not shown it; `version_age_days` is available to campaign conditions).

## [0.5.0] - 2026-11-23

### Changed

- Depends on app-campaign 0.6.0 and app-config 0.2.0 (the campaign and config judges read the
  server-resolved `app_version` range).

## [0.4.0] - 2026-11-22

### Added

- `AppGrowStackCore`: every request carries `AppGrowStack-Device` (`stack.deviceHash`,
  `sha256(publicKey + ":" + device id)` in lowercase hex) and `AppGrowStack-Install` (the install id),
  so the server can tell the owner's own devices from real users. The device id is made once and kept
  in the Keychain (`KeychainAppGrowStackDeviceStore`: generic password, service
  `com.appgrowstack.device`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable),
  so it stays the same across reinstalls and new accounts. If the Keychain cannot be used, it is kept
  in `UserDefaults`. `AppGrowStack.init` takes `deviceStore:`; tests pass `MemoryAppGrowStackDeviceStore`.

## [0.3.0] - 2026-11-22

### Added

- `AppGrowStackCore`: `AppGrowStackAnswer`, the one table every connector reads a status with:
  2xx is `.accepted`; 401, 403, 408, 429 and 5xx are `.retryLater` (a key or a paused project is
  fixed on the server, so the same body passes later); any other 4xx is `.rejected`.

### Changed

- `SupportAppGrowStack`: `submit` returns swift-app-support's `SupportSubmission`. Once the request is
  made, an image that fails is handed back in `unsentImages` instead of throwing, so sending the form
  again no longer makes a second request.
- `LinksAppGrowStack`: statuses are read with `AppGrowStackAnswer`. 404, 409, 413 and 422 are now
  rejected (were tried again on every launch); 401 and 403 are still tried later, up to
  `AttributionReporter`'s `maxAttempts`. The README passes `firstOpenAt: stack.firstSeenAt`.
- `NotificationsAppGrowStack`: statuses are read with `AppGrowStackAnswer`. 401, 403 and 408 throw
  (were taken as done), so the open is kept and sent again.
- `SessionsAppGrowStack`: statuses are read with `AppGrowStackAnswer`. 401 and 403 keep the batch
  (were dropped). A 200 whose body cannot be read (a `replay` this version does not know) takes the
  batch as `.accepted()` instead of throwing, which kept it at the head of the queue.

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
