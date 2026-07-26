# Completion Ledger

- Event-history target acceptance — The typed cursor API is connected through
  the adapter and controller to a server-ordered paginated Events destination
  with refresh, error, retry, end, and page-boundary deduplication behavior.
  Add deterministic controller/widget coverage for multi-page boundary
  deduplication, refresh failure, retry, and long narrow/wide histories, then
  exercise the same states against the packaged targets. No event payload or
  unsafe cursor is persisted.
- Durable port assignments — Parse the canonical assignment collection into
  typed models and expose it before secondary lease controls, with truthful
  retained/active/conflict states and immutable target labels. Verify parser,
  adapter, collection-first wide/narrow UI, and action/status behavior. The
  current Ports destination contains leases only.
- Legacy loopback peer authentication — The bounded, no-redirect public
  `/healthz` marker prevents an accidental wrong-port credential disclosure,
  but another process under the same host trust boundary can imitate that
  public response. Add a canonical authenticated peer-identity mechanism that
  is available to the macOS sandbox (for example a server-authenticated local
  transport or challenge) before calling local v1 production-ready. Verify
  wrong listener, listener replacement between preflight and auth, redirects,
  token non-disclosure, and recovery after coordinator restart.
- Native-v2 target acceptance — The typed `/api/v2` server and consumer, fixed
  production gateway, system-browser OAuth + PKCE/deep links, rotating secure
  device session, capability/scope/grant/action gating, ETags, exact
  idempotent operations, and production deployment are implemented and
  deterministically verified. Complete a physical Android owner
  sign-in/callback/inventory/action/refresh/revocation/offline-recovery journey
  and packaged off-host macOS and Windows sign-in journeys. Remove this item
  only after those target-visible paths are evidenced.
- PostgreSQL protection profile — Server: implement `databases.*` without
  exposing paths/credentials, delegating to the canonical PostgreSQL safety
  workflow and returning immutable checksum, strong restore-test, safety-backup,
  post-restore, cleanup, and rollback evidence. Consumer: add database
  discovery-unavailable, evidence, backup, plan, exact-confirmation, progress,
  failure, and rollback-needed states. Verify disposable-PostgreSQL provider and
  client journeys including mismatched target, stale plan, failed verification,
  cleanup failure, and proof that target mutation cannot precede a strongly
  verified safety backup.
- Routes profile — Server: implement immutable route-instance CRUD, exact
  fixed/server/container targets, resolution state, public-exposure
  acknowledgement, and write-only/redacted upstream credentials. Consumer: add
  collection-first route UI, live slug validation, target selection, private
  default, exact-host public confirmation, copy, retry, and delete flows.
  Verify real HTTP/WebSocket private/public behavior, slug reuse isolation,
  port-change following, credential non-disclosure, and mobile/desktop states.
- Access and incoming-invites profiles — Server: implement immutable
  destination grants, configured-owner immutability, immediate session/grant
  revocation, and an owner decision queue whose requests originate only from a
  verified denial flow with a signed server-derived destination claim.
  Consumer: add owner-only user/grant and pending-first invite collections,
  focused add, exact approve/deny, stale history, and urgent revoke states.
  Verify forged identity/host/instance denial, non-owner denial, duplicate/rate
  handling, stale/reused route isolation, immediate HTTP/WebSocket revocation,
  and narrow/wide accessibility.
- Telegram profile — Server: implement owner-isolated bot credential storage,
  identity validation, explicit webhook takeover, exact project assignment,
  private-`/start` authorization, durable cursor/outbox delivery, restart-safe
  retries, rate-limit handling, and permanent-rejection disablement. Consumer:
  add collection-first registration, redacted token state, assignment, pending
  subscriber decision, error, and destructive removal journeys. Verify with a
  deterministic fake Telegram API and prove no token appears in responses,
  logs, preferences, screenshots, or diagnostics.
- Unassigned-resource profiles — Server: expose observation/controller/
  attribution evidence and current immutable, control-binding, and ownership
  fingerprints; implement exact attach and two-step standalone-retirement
  plans through canonical authority. Consumer: add unassigned collection,
  reason/evidence detail, explicit validated-project selection, plan review,
  exact confirmation, and retained result. Verify same-name collisions,
  missing/non-Git/conflicting/ambiguous/stale evidence, stale fingerprints,
  zero-mutation cancel, attach to exactly one repository, and retirement that
  stops/fences/verifies while retaining files, volumes, databases, backups, and
  history.
- Bulk-stop profile — Server: implement bounded fresh plans for explicit
  server/container ids and durable per-target results. Consumer: add separate
  destructive checkboxes, selected count, reviewed consequences, exact
  confirmation, progress, cancellation, and partial-result retention. Verify
  empty/stale/mixed-state selection, no implicit row selection, bounded
  execution, only checked resources changed, and every outcome visible.
- Performance profile — Server: expose measured host/server/container/project
  samples with timestamps, bounded retention, sampler freshness/error, and
  process-local reset time; never synthesize absent samples. Consumer: add
  numeric current/peak/window labels, decorative accessible charts, stale
  stopped series, host memory/disk/load, and sampler-error states. Verify real
  sampling, ordering and aggregation, history reset, outage/stale behavior,
  bounded payloads, and screen-reader alternatives.
- Publish the selected public repository `PerssKos/DevCoordinatorUniversal`
  and its first stable GitHub Release, then verify anonymous latest-release
  discovery and the in-app newer-version prompt against the published asset.
  The v0.2.0 Android build already embeds that exact release slug; publication
  is blocked until GitHub CLI/app access is authenticated for the `PerssKos`
  account.
- Select the repository and binary distribution license. Until the owner makes
  that policy decision, the repository intentionally has no `LICENSE` file and
  retains the default copyright restrictions; generated package placeholders
  must not be mistaken for an approved open-source license.
- Distribution identities — A dedicated Android direct-distribution key is
  configured outside Git, and the v0.2.0 APK is release-linted, v2/v3-signed,
  zip/page-aligned, and verified against its pinned certificate, package,
  version, merged callback, gateway, update source, and checksum. Confirm an
  offline owner-controlled key backup and real install-over/rollback behavior;
  separately configure Play App Signing, Apple Developer ID or Mac App Store
  signing plus notarization, and Windows trusted MSIX/Store signing.
- Packaged target acceptance — The production-signed Android APK is built, but
  still requires a physical owner sign-in/deep-link/inventory/action/refresh/
  revocation/offline/upgrade/rollback journey. Build and run trusted signed
  macOS and Windows packages and verify the corresponding OAuth, accessibility,
  update-channel, loading/empty/populated/long/offline/partial/
  capability-blocked, responsive, upgrade, and rollback journeys. Linux
  analysis/widget tests and compile-smoke packages do not prove target package
  readiness.
