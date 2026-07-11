# AGENTS — maintaining the API2Convert Ruby SDK

This SDK is **hand-written** (not generated from OpenAPI) and kept in sync with the API by a human
**or an AI agent**. This file is the playbook. The model: a committed spec snapshot is the diff
baseline, a fixed behavior contract protects the ergonomics, and the RSpec suite is the guardrail.

It is one of five official ports (PHP, Python, Java, Node.js, Ruby) that all implement the same
language-agnostic contract in [`docs/SDK_CONTRACT.md`](docs/SDK_CONTRACT.md).

## Why hand-written

The conversion flow is multi-step (create → upload → poll → download) and the **upload step is not in
the OpenAPI spec at all**, so a generator cannot produce a usable client. We optimise for a
junior-friendly surface — one-call `convert` — and use AI to keep it current.

## Repo layout

| Path                                     | What it is                                                                       |
| ---------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/api2convert/client.rb`              | The client + the `convert` / `convert_async` façade. **Hand-authored.**          |
| `lib/api2convert/result.rb`              | `ConversionResult` + `FileDownload` helpers. **Hand-authored.**                  |
| `lib/api2convert/upload/*`               | Streamed multipart upload to the per-job server. **Hand-authored** (not in spec).|
| `lib/api2convert/webhook/*`              | Webhook HMAC verification + parsing. **Hand-authored.**                          |
| `lib/api2convert/resource/*`             | One class per API tag (Jobs, Conversions, Presets, Stats, Contracts). **Derived.**|
| `lib/api2convert/model/*`, `*_status.rb` | Value objects (`from_hash` factories) / enum modules. **Derived** from the spec. |
| `lib/api2convert/http/*`                 | Transport: auth, retries/backoff, error mapping, redirect policy, the sender seam.|
| `lib/api2convert/errors.rb`              | The typed exception hierarchy.                                                   |
| `openapi/api2convert.openapi.json`       | **Committed spec snapshot** the SDK targets — the diff baseline (md5-identical to siblings). |
| `docs/SDK_CONTRACT.md`                   | The fixed, language-agnostic public surface + semantics (md5-identical to siblings). |
| `spec/unit/*`                            | Offline golden specs (`FakeHttpSender`). **The guardrail.**                      |
| `spec/security/*`                        | The independent security suite (real loopback servers). **The redirect/leak guardrail.** |
| `spec/live/*`                            | Live conformance (auto-skips without `API2CONVERT_API_KEY`).                     |

## How to update the SDK to a new API version

1. **Refresh the snapshot.** Overwrite `openapi/api2convert.openapi.json` from
   `https://api.api2convert.com/v2/openapi.json` (or `/v2/schema`) and `git diff` it.
2. **Diff it** — new/removed/renamed operations, new fields, new enum values.
3. **Update the DERIVED layer to match the diff, and nothing else:**
   - New/changed fields → update the relevant `model/*` class + its `from_hash`.
   - New operation → add a method on the matching `resource/*` class (mirror the existing style).
   - New input/output target types → extend `job_status.rb` / `input_type.rb`.
4. **Do NOT change the hand-authored public API** (`convert`, `convert_async`, `download`, upload,
   `wait`, webhook verification, error classes) unless `docs/SDK_CONTRACT.md` changes first. If a
   real product change requires it, update the contract in the same change and bump the **major**
   version.
5. **Lint + test (the guardrail):**
   ```console
   bundle exec rake check   # rubocop + unit specs + security suite — all must pass
   ```
   Add or update a golden spec for any new behavior. Keep the live conformance spec runnable.
6. **Record + version.** Add a `docs/CHANGELOG.md` entry and bump `Api2Convert::VERSION` per SemVer
   (additive spec change → minor; breaking public-surface change → major). The five SDKs version
   together against the shared contract.

## Guarantees to uphold (don't break these)

- **Never commit a real API key, token or secret** — not in source, specs, fixtures, examples, CI
  files or commit messages. Keys come only from environment variables (`API2CONVERT_API_KEY`) or
  masked/protected CI variables; specs use obvious fakes (`test-key`, `secret-key`, `whsec_test`).
  The behat test keys live only in the `behat-api` repo's `behat.yml.dist_*` — supply one via the
  env var when running `rake spec:live`, never paste it here. The SDK must never log or expose a
  key/token in errors. Secret-scan before any release.
- **The contract is law.** Public method names, signatures and semantics match `docs/SDK_CONTRACT.md`
  across every SDK language. Adapt only to Ruby idiom (see divergences below).
- **Upload uses the per-job `X-Api2convert-Token`, never the account key.** There is a spec for this.
- **Secret-bearing requests never follow redirects.** The key/token/download-password ride in custom
  `X-Oc-*` headers. `Net::HTTP` does not follow redirects by default — the SDK relies on that and
  only opts the no-secret download path into following redirects. `spec/security` proves the
  guarantee with real loopback servers.
- **`convert` stays one call** for the common case (path/URL/IO → `to` → `save`).
- **Transient failures retry; failures surface as typed exceptions.** Never leak a raw
  `Net::HTTP`/socket error (wrap it in `NetworkError`). A non-idempotent `POST` is never blindly
  retried.
- **Ruby 3.1+, zero runtime dependencies, standard library only.** Don't add runtime deps.

## Ruby-idiom divergences from the contract

The contract fixes names and semantics; these are the _only_ places Ruby deviates, all for idiom:

- **The client is `Api2Convert::Client`** (a module namespace can't be instantiated); the module-level
  `Api2Convert.webhooks` mirrors the contract's client-less webhook verifier.
- **Method and option names are `snake_case`** (`convert_async`, `add_input`, `download_password`,
  `poll_interval`).
- **The "extra" `convert` controls are Ruby keyword args** (`category:`, `timeout:`, `output_index:`,
  `filename:`, `download_password:`), kept separate from the open-ended positional `options` Hash so
  API option keys can never collide with SDK keys.
- **Exceptions are named `...Error`** and extend `StandardError`; the poll timeout is
  `ConversionTimeoutError` (not shadowing `Timeout::Error`).
- **`Job` exposes predicates** `completed?` / `failed?` / `canceled?` / `terminal?` and keeps `raw`.
- **Models are frozen value objects with `from_hash` factories**, hydrated defensively via
  `Support::Data` (tolerate missing/extra fields — never raise on a surprising payload).
- **The HTTP sender is a seam**: `Client.new(..., http_sender:, sleeper:, rng:)` injects a fake for
  unit specs; the default is `Http::NetHttpSender`.

## Conventions

- Resource methods are thin: build the request, call `Transport`, hydrate a model.
- Keep the README quickstart copy-pasteable; if you change the happy path, update the README example.
