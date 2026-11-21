# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `AppGrowStackCore`: `AppGrowStack`, the one value the connectors read (public key, environment,
  lowercase install id, first-seen date, recent activity, the `AppGrowStack-Client` header).
- Connector targets are added per SDK behind a trait of the same name, so an app fetches only the
  SDKs it enables.
- `LinksAppGrowStack` (trait `Links`, swift-app-links 0.2): `stack.attributionResolver()` decides the
  install's source with `POST /v1/links/attributions`.
- `SupportAppGrowStack` (trait `Support`, swift-app-support 0.2): `stack.supportTransport()` (requests,
  screenshots, replies with the owner token in the Keychain, help articles on `/v1/support/*`) and
  `stack.supportContext()` (the context with the stack's recent activity).
