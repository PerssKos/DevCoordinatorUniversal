# DevCoordinator Universal Agent Instructions

These rules apply to the whole repository.

## Product and source boundaries

- This repository owns only the cross-platform client, its design system,
  typed client contracts, tests, and release automation.
- `/home/Coordinator/DevCoordinator` remains the canonical owner of the host
  broker, normalized coordinator store, process and Docker lifecycle logic,
  PostgreSQL safety logic, Console access policy, and server-side routes.
- Never copy the coordinator database schema, private token files, access
  policy, or privileged lifecycle implementation into this repository.
- The legacy coordinator HTTP API is loopback-only. Permit it only as an
  explicit local desktop connection. Never offer its host-wide bearer token as
  a mobile or general remote-access credential.
- Remote clients require the versioned native gateway contract documented in
  `contracts/native-gateway.openapi.yaml`. Capability-gate functionality that
  the connected server does not advertise.

## Truthful behavior

- No production screen may contain synthetic inventory. Fixtures belong only
  in tests and screenshot/golden harnesses.
- Treat HTTP 200 responses carrying `ok: false`, `partial: true`,
  `needs_attention: true`, or a blocked/failed/partial status as failures.
- Every destructive action must name its exact target, show the server plan or
  consequences, require explicit confirmation, and retain the returned result.
- Never log, serialize into preferences, or send to crash reporting any
  access token, refresh token, coordinator bearer, signing key, or raw
  authorization header.

## Architecture

- Features depend on domain/client interfaces and semantic `App*` design
  components, not platform storage or raw HTTP implementations.
- Keep visual style (`oneUiInspired`, `cupertino`, `material`) independent from
  brightness preference (`system`, `light`, `dark`).
- Add styles through semantic tokens and component renderers. Do not copy
  Samsung or Apple proprietary assets or fonts.
- Shared preferences are only for non-secret preferences. Secrets use the
  `SecureTokenStore` interface and platform-backed implementation.
- Keep one root Pub workspace and lockfile. Do not add nested lockfiles.

## Updates and releases

- Update checks compare installed SemVer with published releases, not commits.
- GitHub release checks are notification-only. Distribution-channel installers
  remain distinct: Play builds use Play mechanisms, Store builds use their
  stores, and direct builds open signed release assets/pages.
- Do not embed a GitHub personal access token. Private-repository update access
  requires an approved user-authenticated or server-side design.
- Never publish unsigned production artifacts. CI smoke artifacts must be
  clearly named and must not be attached to a production release.

## Verification

- Run `dart pub get`, `dart format --output=none --set-exit-if-changed .`,
  `flutter analyze`, and all workspace tests before readiness.
- Build each target on its required host: Android on Linux, macOS on macOS, and
  Windows on Windows. A Linux-only check is not evidence that desktop packages
  launch on macOS or Windows.
- Test loading, empty, populated, long-content, offline, authentication,
  capability-blocked, partial-result, and recovery states at narrow and wide
  viewports.

## Shared-host toolchains

- Prefer workspace-local SDK archives over installing host packages. Before
  any unavoidable package-manager transaction, inspect coordinated service
  state and prevent unattended service restarts (on this Ubuntu host, set
  `NEEDRESTART_MODE=l` and invoke it through
  `tool/run_host_package_command.sh`). Treat a package transaction and any
  later service restart as separate reviewed operations.
- If a toolchain install nevertheless changes a running service, preserve the
  journal evidence and verify its real group/permission boundary, anonymous
  health, authenticated inventory, and dependent public health surface before
  continuing. User-namespace sandbox ownership output is not host evidence.
