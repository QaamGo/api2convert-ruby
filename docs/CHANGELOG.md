# Changelog

All notable changes to the API2Convert Ruby SDK are documented here. The five
official SDKs (PHP, Python, Java, Node.js, Ruby) version together against the
shared [`SDK_CONTRACT.md`](SDK_CONTRACT.md).

## 10.2.0

Initial release of the Ruby SDK — a peer port implementing the shared
API2Convert SDK contract.

- One-call `Api2Convert::Client#convert` (local path / URL / IO → target → `save`),
  plus `convert_async` for the callback/polling flow.
- Full job lifecycle via `client.jobs` (`create`, `get`, `list`, `update`, `start`,
  `cancel`, `add_input`, `upload`, `wait`, `outputs`) and the `conversions`,
  `presets`, `stats`, `contracts` resources.
- Streamed multipart upload to the per-job server, authenticated with the per-job
  `X-Oc-Token` (never the account key).
- Password-protected downloads that remember the password and apply it automatically.
- Webhook HMAC-SHA256 verification (`Api2Convert.webhooks`).
- Typed exception hierarchy; capped, jittered retry with `Retry-After` support;
  bounded job polling.
- Zero runtime dependencies (Ruby standard library only).
- Independent security suite proving, with real loopback servers, that secret
  `X-Oc-*` headers are never forwarded across a cross-host redirect.
