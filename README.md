# DevCoordinator Universal

An installed DevCoordinator client for Android, macOS, and Windows with an
original One UI-inspired style, Cupertino and Material alternatives, and
independent system/light/dark appearance.

The repository intentionally contains no coordinator authority, database, or
privileged host lifecycle implementation. It consumes a typed server contract
and keeps the current legacy host bearer only in process memory. Future
installed-client OAuth credentials belong behind a separate platform-backed
secure-store adapter.

## Current capability

- Local macOS client for the existing loopback coordinator API, with a public
  exact-service preflight before the user-supplied host credential is used.
  The bearer is never persisted and must be entered again after app restart.
- Typed inventory for projects, servers, containers, active/retained port
  leases, a bounded recent-event snapshot, and backup evidence. Full event
  cursor history and durable port assignments remain in the completion ledger.
- Exact server and project actions, logs, and port leases when the connected
  connection contract supports them, with stale-data and partial-result
  fail-closed handling. Container lifecycle stays disabled on legacy v1
  because that API targets a mutable name rather than an immutable container
  identity.
- Responsive phone/desktop shell and runtime-switchable style/brightness.
- GitHub Release update checks with SemVer, ETag caching, ignore/later policy,
  and channel-specific handoff.
- A versioned native-gateway contract plus an independently tested HTTPS core
  client for safe Android and remote access. The provider, installed-client
  OAuth flow, and application adapter remain intentionally unwired.

Android, Windows, and off-host control are intentionally unavailable until the
server-side native gateway is deployed. The existing host-wide loopback token
is not a mobile or Windows-host credential. The macOS legacy path is also a
local preview, not a production trust boundary, until its server identity is
bound cryptographically or by an equivalent authenticated local transport.

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
so its ephemeral build-smoke binaries target that repository's Releases. The
workflow validates builds but deliberately does not upload unsigned
installers. For a local build, pass
`--dart-define=UPDATE_REPOSITORY=owner/repository`. An optional
`UPDATE_DESTINATION_URL` must be HTTPS.

See [architecture](docs/architecture.md), [extension guide](docs/extending.md),
[release operations](docs/releasing.md), and the active
[completion ledger](CompletionLedger.md).
