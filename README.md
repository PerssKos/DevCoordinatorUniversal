# DevCoordinator Universal

An installed DevCoordinator client for Android, macOS, and Windows with an
original One UI-inspired style, Cupertino and Material alternatives, and
independent system/light/dark appearance.

The repository intentionally contains no coordinator authority, database, or
privileged host lifecycle implementation. It consumes the typed HTTPS native
gateway, uses system-browser OAuth Authorization Code + PKCE, keeps access
tokens in memory, and stores only the rotating refresh credential in the
platform secure store. The legacy local-host bearer remains process-only.

## Current capability

- Local macOS client for the existing loopback coordinator API, with a public
  exact-service preflight before the user-supplied host credential is used.
  The bearer is never persisted and must be entered again after app restart.
- Typed inventory for projects, servers, containers, active/retained port
  leases, paginated event history, and backup evidence. Durable port
  assignments and final event-history target acceptance remain in the
  completion ledger.
- Exact server and project actions, logs, and port leases when the connected
  connection contract supports them, with stale-data and partial-result
  fail-closed handling. Container lifecycle stays disabled on legacy v1
  because that API targets a mutable name rather than an immutable container
  identity.
- Responsive phone/desktop shell and runtime-switchable style/brightness.
- GitHub Release update checks with SemVer, ETag caching, ignore/later policy,
  and channel-specific handoff.
- A versioned native-gateway contract and application adapter for Android and
  remote desktop access, with system-browser sign-in, exact deep-link
  callbacks, current scope/grant checks, strong ETags, and repeat-safe
  mutations by immutable resource ID.

The production Android setup is deliberately one action: connect to
`https://console.classified.guru/api/v2`, sign in with the system browser, and
return to the app. It never asks for a hostname, coordinator token, or “local
desktop” mode. Windows and macOS can use the same remote flow; macOS also keeps
an explicitly labeled legacy local preview. The host-wide loopback token is
never a mobile or Windows credential.

## Development

Flutter 3.44.8 and Dart 3.12.2 were used for the initial workspace. The
OpenAPI verifier additionally uses Python dependencies locked with hashes in
`tool/requirements-openapi.txt`.

```bash
flutter pub get
python -m pip install --require-hashes \
  --requirement tool/requirements-openapi.txt
python tool/validate_native_gateway.py \
  --self-test contracts/native-gateway.openapi.yaml
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/coordinator_client
flutter test packages/devcoordinator_design
flutter test packages/release_update
flutter test apps/devcoordinator
cd apps/devcoordinator
flutter run -d <device>
```

GitHub Actions injects the current `owner/repository` into every target build,
so its ephemeral build-smoke binaries target that repository's Releases.
Android debug and unsigned-release smokes are compiled but never uploaded.
The workflow retains a clearly labeled, symlink-preserving ad-hoc macOS ZIP
with its SHA-256 checksum and a self-signed Windows smoke artifact for seven
days so target compilation and packaging can be inspected. The macOS bundle is
verified both before archiving and after a `ditto` round trip. These artifacts
are not production installers and are never attached to a stable Release. For
a local build, pass
`--dart-define=UPDATE_REPOSITORY=owner/repository`. The optional
`UPDATE_DISTRIBUTION_CHANNEL` is one of `direct`, `play`, `mac_app_store`, or
`microsoft_store` and must match the build platform; it defaults to `direct`.
Direct builds reject `UPDATE_DESTINATION_URL` and open only their verified
installer asset. Store builds require their exact official
`UPDATE_DESTINATION_URL`; Mac App Store and Microsoft Store builds also require
the product identity assigned by the Store in `UPDATE_STORE_PRODUCT_ID`.

Direct update checks read a bounded stable-release catalog and select the
highest newer release containing the exact owned target asset:
`DevCoordinator-<version>-android.apk`,
`DevCoordinator-<version>-macos.dmg`, or
`DevCoordinator-<version>-windows.msix`. An Android-only release is therefore
never presented as a macOS or Windows update. Store discovery likewise
requires an exact repository-owned
`DevCoordinator-<version>-<platform>-<store>-<product-id>.release.json` marker
uploaded only after that version is visible for the same application identity
in the matching Store.

See [architecture](docs/architecture.md), [extension guide](docs/extending.md),
[release operations](docs/releasing.md), and the active
[completion ledger](CompletionLedger.md).
