# Completion Ledger

- Full event history — Connect the typed cursor API to the application adapter,
  controller, and Events destination instead of relying on the bounded
  inventory snapshot. Persist only a safe checkpoint, preserve server order,
  deduplicate page boundaries, expose loading/error/end/retry states, and test
  refresh plus long histories. Until then the UI must identify events as a
  recent snapshot rather than durable cursor history.
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
- Native-v2 core — Server: implement and deploy `/api/v2` HTTPS, Authorization
  Code + PKCE S256, short-lived user access tokens, rotating/revocable device
  sessions, per-resource grants, capability discovery, ETags, idempotency,
  RFC 9457 errors, and durable operations. Consumer: implement native
  system-browser sign-in, PKCE/deep-link handling, secure refresh-token
  rotation/revocation, v2 connection composition, minimum-client negotiation,
  platform redirect declarations, application-state adapters, and
  scope/grant/action gating. Verify
  provider/OpenAPI conformance plus Android and off-host desktop auth, denial,
  expiry, refresh, revocation, idempotent retry, offline recovery, and partial
  failure. Until then those connection modes remain intentionally blocked.
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
- Windows host authority — Design and implement a separately secured canonical
  Windows service for process, Docker, port, PostgreSQL, and lifecycle
  authority, or explicitly limit Windows to remote native-v2 operation. The
  desktop app must not become privileged authority. Verify service identity,
  ACLs, concurrency, recovery, and exact action routing on Windows.
- Select the canonical GitHub repository visibility/name and publish it, then
  set the release source used by production builds. Anonymous GitHub update
  checks require a public repository; a private repository needs approved user
  authentication or a backend GitHub App.
- Select the repository and binary distribution license. Until the owner makes
  that policy decision, the repository intentionally has no `LICENSE` file and
  retains the default copyright restrictions; generated package placeholders
  must not be mistaken for an approved open-source license.
- Configure stable application/store identities and production signing:
  Android upload/Play signing, Apple Developer ID or Mac App Store signing plus
  notarization, and Windows trusted MSIX/Store signing. Verify install-over-
  previous-version and rollback on real target machines.
- Run signed packaged launch, accessibility, update-channel, loading/empty/
  populated/long/offline/partial/capability-blocked, and responsive journeys on
  physical Android, macOS, and Windows systems. Linux analysis and widget tests
  do not prove target packaging or launch readiness.
