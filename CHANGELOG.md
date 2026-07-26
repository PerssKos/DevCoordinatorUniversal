# Changelog

All notable changes to this repository follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Semantic
Versioning.

## [Unreleased]

## [0.2.1] - 2026-07-26

### Changed

- Update discovery now reads a bounded, ETag-cached stable-release catalog
  and selects only the highest newer release with an exact owned asset for the
  installed platform and distribution channel.
- Provider responses are streamed through byte and structural limits;
  unrelated malformed/non-SemVer entries no longer hide valid releases, and
  comparisons now follow SemVer 2.0 without build-metadata precedence.
- macOS CI smoke output is verified and archived with `ditto`, preserving
  framework symlinks and rechecking the extracted universal ad-hoc bundle
  before upload.
- Android debug and profile variants use visibly distinct application names;
  the production APK verifier now also pins the exact release label.

### Fixed

- A failed event-history refresh no longer clears the previously committed
  events or cursor; the retained page stays visible and retryable.
- Published Android certificate verification now accepts equivalent
  `apksigner` output formats across supported Android SDK versions.
- macOS release/profile configuration now explicitly builds both `x86_64` and
  `arm64`, independent of the CI runner architecture.

### Security

- Direct update eligibility requires one exact, fully uploaded, non-empty
  asset whose HTTPS download path belongs to the configured repository, tag,
  and target filename. Android-only releases are not offered to macOS or
  Windows.
- Direct handoff cannot be redirected away from the verified installer asset.
  Store releases require an exact platform/channel/product-identity marker and
  an official listing URL tied to the same build-pinned Store identity.

## [0.2.0] - 2026-07-26

### Added

- Flutter workspace and installed Android, macOS, and Windows runners.
- Original One UI-inspired, Cupertino, and Material style packs with
  independent system/light/dark appearance and high-contrast variants.
- Typed, fail-closed legacy coordinator client for verified local macOS use.
- Responsive resource collections, capability-gated operations, session-only
  legacy credentials, stale/read-only recovery, and retained operation results.
- GitHub Release notifications with SemVer, ETag caching, ignore/remind-later,
  and HTTPS distribution-channel handoff.
- OpenAPI 3.1 native-gateway contract, strict validator, CI quality gates, and
  per-platform build-smoke jobs.
- Independently testable Native Gateway v2 core client with typed DTOs,
  HTTPS-only requests, strong ETags, idempotency keys, RFC 9457 failures,
  bounded payloads, and durable-operation semantics.
- Fixed production connection to `https://console.classified.guru/api/v2`
  with one-action system-browser OAuth Authorization Code + PKCE sign-in,
  platform deep-link callbacks, rotating secure device sessions, and no
  hostname, coordinator-token, or local-desktop prompt on Android.
- Native collection screens for authorized projects, servers, containers,
  recent events, logs, and port leases with server-advertised capability,
  scope, grant, action, and blocker gating.

### Security

- Remote and non-macOS clients cannot reuse the host-wide loopback credential.
- Mutation timeouts become an explicit unknown-outcome state that requires a
  fresh authoritative refresh before another mutation.
- Post-dispatch transport failures and malformed, oversized, or
  schema-invalid successful native-v2 mutation responses also become explicit
  unknown outcomes; determinate RFC 9457 rejections remain ordinary failures.
- Legacy localhost setup validates an exact public service marker before
  reading the host bearer and never follows HTTP redirects. Cryptographic
  local peer authentication remains an explicit readiness blocker.
- Container log reads require a full immutable Docker ID, and duplicate
  visible resources receive deterministic safe labels in confirmations and
  retained operation results.
- Legacy server controls use a closed lifecycle/health matrix, retained or
  expired leases cannot be released, and port creation requires selection of
  an exactly owned enrolled server from the current inventory.
- Android excludes application data and secure-storage metadata from cloud,
  legacy, and device-to-device backup paths.
- Android direct-distribution releases use a dedicated stable signing
  certificate so future APK updates can retain one package identity.
- The Android OAuth callback declares an exact authority and path in the
  merged APK; release lint and artifact validation reject broader handlers.
- Stable releases are staged as drafts, downloaded, and revalidated before
  publication; Android debug APKs are never distributed.
- The direct Android signing key remains outside GitHub; a local fail-closed
  publisher uploads only signed assets, and read-only Actions verifies them.
- The host-wide legacy bearer is never persisted by current builds. A cold
  process cannot recover the old durable key, even when marker, profile, and
  key deletion all failed during disconnect.
- Disconnect drops the session bearer before fallible legacy-key cleanup;
  failed cleanup blocks new connections and exposes an explicit retry.
