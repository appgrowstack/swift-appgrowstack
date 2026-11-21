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
