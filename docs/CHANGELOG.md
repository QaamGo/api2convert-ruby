# Changelog

All notable changes to the API2Convert Ruby SDK are documented here. The five
official SDKs (PHP, Python, Java, Node.js, Ruby) version together against the
shared [`SDK_CONTRACT.md`](SDK_CONTRACT.md).

## [10.3.2] - 2026-08-12

### Fixed

- Replaced the trailing-separator regex trims (`%r{/+\z}`) in `config.rb`, `result.rb` and
  `file_uploader.rb` with a linear reverse scan (`Support::Strings.trim_trailing`). CodeQL
  flagged the patterns as polynomial ReDoS: a string ending in a long run of separators cost
  O(n²), and `job.server` comes from the API while `base_url` comes from caller config.
  Identical semantics, linear time.

## [10.3.1] - 2026-07-12

- Ships the cloud-storage examples added to the README (READMEs are included in the published
  gem). No functional or API change from 10.3.0.

## [10.3.0] - 2026-07-12

### Added

- Cloud-storage connectors: typed `CloudInput` + `OutputTarget` (SDK contract D-5).
- On-brand `x-api2convert-*` request headers.

### Fixed

- Bounded the control-plane response-body read; atomic save, download error typing and numeric
  overflow safety (Track B robustness); a 3xx on the authenticated JSON path now raises a typed
  error instead of returning an empty model.

## [10.2.1] - 2026-07-08

- Lock-step version bump to keep all API2Convert SDKs on 10.2.1. No library changes since 10.2.0
  (the redirect / download-password hardening already shipped); added a runnable example per
  documented guide and expanded the live-conformance suite to seven canonical scenarios.
