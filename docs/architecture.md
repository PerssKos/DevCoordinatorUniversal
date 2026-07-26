# Architecture

## Repository map

```text
apps/devcoordinator/              composition root and platform runners
packages/coordinator_client/      typed domain models and transport adapters
packages/devcoordinator_design/   semantic tokens and switchable style packs
packages/release_update/          provider-neutral release/update decisions
contracts/                        native gateway contract and deferred profiles
docs/                             product, architecture, release operations
```

Features do not own transport, credential storage, or update policy. The app
composition root injects those services and exposes immutable view state.

## Release discovery boundary

Update checks read a bounded, ETag-cached catalog of stable GitHub Releases.
The application build supplies one explicit platform and distribution
channel. A direct build selects the highest newer SemVer containing exactly
one non-empty canonical-repository asset named for that target; Play, Mac App
Store, and Microsoft Store builds require a matching channel, an exact
repository-owned platform/channel/product-identity marker uploaded after Store
publication, and an official Store destination tied to that same identity.
Drafts, prereleases, foreign URLs, incomplete assets, smoke artifacts, and
assets for another platform are never eligible. An unrelated malformed
release entry is ignored rather than hiding an older valid target.

The catalog is notification metadata, not an installer authority. Android,
Apple, and Windows package signatures remain the installation identity, and
the application never executes or silently installs an arbitrary release
asset. Direct handoff opens the verified owned installer URL itself; it cannot
be redirected with a build-time destination override.

## Connection modes

### Local legacy v1

Supported only on macOS when the app and coordinator run on the same verified
host. The endpoint validator accepts only IPv4 loopback/`localhost` HTTP URLs.
Before reading the bearer, the client performs a bounded, no-redirect,
unauthenticated `/healthz` request and requires the canonical exact service
marker. The user-supplied bearer exists only in memory for the current app
process; a cold launch never recovers it from preferences or secure storage.
The non-secret host profile remains available to prefill the connection form.
Windows does not expose this mode until a canonical Windows host authority
exists.

### Native gateway v2

Required for Android and off-host clients. It is HTTPS-only and begins with a
capabilities/meta exchange. A server without the required contract is shown as
incompatible; the client does not fall back to the host-wide v1 credential.

The gateway is a translation and authorization boundary, not a second
coordinator. It owns installed-client OAuth/OIDC sessions, scopes, remote DTOs,
rate limits, and redaction, then delegates every host mutation to the canonical
DevCoordinator authority. It never gives the app a coordinator token, database
path, Docker socket, arbitrary command, or raw policy store.

## Capability profiles

`contracts/native-gateway.openapi.yaml` contains a required core and optional
profiles. Optional paths carry both
`x-devcoordinator-capability: <exact-id>` and
`x-implementation-status: deferred`. The marker means “use this DTO if a
provider implements and advertises this profile,” not “this endpoint is
deployed.”

| Profile | Conditional path roots | Required caller scopes |
| --- | --- | --- |
| PostgreSQL database protection | `/databases`, `/database-restore-plans` | `databases:read`, `databases:protect`, `databases:restore` |
| Routes | `/routes` | `routes:read`, `routes:manage`, optionally `routes:credentials` |
| Access and invite decisions | `/access/users`, `/access/requests` | `access:manage`, `invites:manage` |
| Telegram | `/telegram` | `telegram:manage` |
| Unassigned correction | `/unassigned-resources`, `/unassigned-retirement-plans` | `unassigned:read`, `unassigned:manage` |
| Explicit bulk stop | `/bulk-operation-plans` | `bulk:act` |
| Performance history | `/performance/history` | `performance:read` |

Capability strings are open for compatible future additions. The application
recognizes only exact known identifiers and ignores unknown identifiers. A
profile is usable only when all four layers agree:

```text
server capability ∩ user scope/grant ∩ object allowed-action ∩ fresh revision
```

This repository must keep an independently testable feature adapter for each
profile. Adding a new style pack does not change those adapters; adding a
profile does not let a feature bypass semantic `App*` controls or the central
action/result state.

## Native session and secret boundary

The system browser performs Authorization Code + PKCE S256. Access tokens are
short-lived; refresh-token families rotate and bind to a revocable device
session. The secure store holds only the installed-client credentials issued
to that user/device. Preferences, logs, diagnostics, crash reports, and update
requests never receive them.

The legacy loopback bearer is session-only. Current builds delete, but never
read, the old secure-storage key used by earlier builds. A cold process starts
without a credential even if the previous disconnect could not persist its
cleanup marker, delete that old key, or clear the profile. Disconnect still
records a non-secret pending-cleanup gate and retries legacy-key deletion; a
failure blocks new connections and exposes an explicit retry. The user must
enter the host token after every app restart. Cold launch attempts the exact
legacy-key deletion unconditionally, including when no profile or marker
remains; that purge is separate from reading the process-session bearer.
A transient first purge failure is retried before treating cleanup as
unresolved, and a successful retry retains the non-secret saved host profile.
The profile is removed only when that cold-launch cleanup remains unresolved.

Native-v2 refresh credentials are a separate credential class. They rotate in
their own revocable device-session family, use the platform secure-store
adapter, and never reuse the legacy host-token path.

Route upstream credentials and Telegram bot tokens are write-only request
fields. The gateway returns only redacted presence/scheme state. Access-request
creation is deliberately absent from the installed-client mutation surface:
the protected destination creates it from a verified identity and a
short-lived signed claim for that exact immutable destination. The app only
consumes the owner decision queue.

## Mutation safety

All optional-profile mutations follow the same primitives as core lifecycle:

- an opaque immutable target rather than a display name or reusable slug;
- a strong `If-Match` revision and UUID idempotency key;
- server-authored blockers and allowed actions;
- plan/fingerprint/expiry/exact-phrase apply for database restore,
  standalone retirement, and bulk stop;
- durable operation polling with per-target results; and
- refresh of authoritative inventory after completion.

Once a mutation is dispatched, a timeout, transport break, oversized or
malformed success response, or success-schema failure is reported as an
inconclusive outcome rather than a definite failure. Recovery must query
authoritative state with the same idempotency context; it must not blindly
retry with a new key.

`succeeded` is the only successful terminal operation state, and only when
`partial` and `needsAttention` are both false and every target result
succeeded. Database restore plans always require strong incoming-backup
verification and a new strongly verified safety backup. Standalone retirement
has an empty deleted-data set. Bulk stop is bounded to explicit checked ids.

## Current implementation boundary

The deployed required core has a strict, independently tested HTTPS boundary
for meta, session, inventory, events, logs, exact resource actions, port
leases, RFC 9457 failures, and durable operations. It enforces strong ETags,
UUID idempotency, bounded payloads, credential redaction, fail-closed partial
inventory, system-browser OAuth/PKCE, and rotating secure refresh credentials.
The application adapter composes that core against the fixed production
gateway on Android and remote desktops.

Lifecycle planning and every optional profile in the table remain
capability-gated active work. Their schemas and client primitives prevent
incompatible ad-hoc endpoints, client-side authority, or false UI promises,
but do not claim that the provider advertises them. Until the corresponding
ledger item is closed with provider and consumer evidence, the app must show a
capability blocker and no action control for that family.

## Data flow

```text
View → AppController → CoordinatorGateway → typed HTTP contract
  ↑          ↓
design   immutable AppState
tokens       ↓
        session bearer + non-secret preferences
```

All actions refresh server truth after completion and retain the typed result.
Partial/incomplete coordinator reports are errors even when HTTP transport
succeeds.
