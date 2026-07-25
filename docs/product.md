# Product contract

## Promise

Give a developer or operator one truthful installed client for the exact
DevCoordinator resources they are authorized to see and control. The client
must work well one-handed on Android, at desktop density on macOS/Windows, and
must never imply that cached or capability-blocked data is live.

## Users and authorization

- Configured owner: all granted operational actions plus access, lifecycle,
  route, and notification administration.
- Invited operator: explicitly granted operations; no implicit access
  administration or permanent removal.
- Route-only user: the exact protected route, not the operational client.
- Verified requester: may request the exact denied resource; verification is
  not a grant.
- Telegram bot owner/subscriber: separately authorized notification role.

The server remains authoritative for identity, scopes, resource grants,
allowed actions, blockers, and lifecycle plans.

## Delivery truth

The implemented client can use the loopback legacy contract only on the same
macOS host. Android, Windows, off-host desktop, and every native-v2-only family
below remain unavailable until both sides of the contract exist:

1. DevCoordinator/DevOpsConsole implements and deploys the server-owned
   profile with user-scoped authentication and contract tests.
2. This repository implements the typed consumer, states, actions, and
   end-to-end tests.

An OpenAPI path marked `x-implementation-status: deferred` is a conditional
interface definition, not evidence that either side is working.

## Navigation

The first release shell reserves stable destinations for:

1. Overview — current health, partial/offline warning, resource counts, recent
   events, and the exact items needing attention.
2. Projects — canonical Git projects, their server/container/database members,
   measured usage, and whole-project actions.
3. Servers — project-grouped services, health, port, process facts, logs, and
   exact start/stop/restart actions.
4. Containers — image, state, ports, usage, logs, and exact Docker actions.
5. Ports — the active/retained lease snapshot, expiry, exact release, and
   creation against an enrolled server. Durable port-assignment browsing
   remains unresolved in the completion ledger.
6. Events — the bounded recent inventory snapshot. Full durable cursor history
   remains unresolved in the completion ledger.
7. Settings — connection/security status, visual style, brightness, update
   channel, version, and diagnostics.

Server capabilities later reveal Routes, Performance, Databases, Access,
Invites, Telegram, Archived resources, and Unassigned resources without
changing the shell contract.

## Primary interaction rules

- A collection destination leads with its real items or honest
  loading/error/empty state. Creation is a toolbar action and opens a focused
  dialog or narrow-screen sheet.
- A resource row shows display name, project, state text plus color, and the
  few actions currently allowed by the server. Details progressively disclose
  immutable identity, provenance, diagnostics, metrics, and operation results.
- Start, stop, restart, logs, lease, archive, restore, purge, attach, retire,
  backup, verify, and database restore always target an immutable server
  identity.
- Destructive actions never reuse ordinary row selection. Bulk stop requires
  explicit checked resources, a count, confirmation, and per-item results.
- Archive/restore/purge display the server-authored effects, retained/deleted
  data, blockers, plan fingerprint, and exact confirmation phrase. Restore
  never implies start.
- Offline cached inventory is visibly stale and read-only. Mutations require a
  fresh authenticated revision.

## Required states

- Bootstrap, first connection, authentication, loading, empty, populated, long
  content, partial, stale, offline, incompatible server, and minimum-client
  upgrade required.
- Running, stopped, starting, stopping, unhealthy, wrong listener, archived,
  unknown ownership, and capability blocked.
- Action queued, running, succeeded, failed, timed out, cancelled, partial, and
  needs attention, with retained user-visible result.
- Logs loading, empty, truncated, unavailable, and refresh failure.
- Lease active, expiring, expired, released, conflicted, and failed.
- Database discovery unavailable, unprotected, checksum verified, restore
  tested, verification failed, restore planned/running/succeeded, and rollback
  needed.
- Route empty, invalid/reserved/duplicate slug, unresolved target, login
  required, public-confirm pending, public, credential configured/redacted, and
  save/delete conflict.
- Access owner-only/empty/populated, owner immutable, grant saving/revoked,
  invite pending/approved/denied/stale/duplicate/rate-limited, and decision
  conflict.
- Telegram empty, registering, webhook conflict/takeover, assigned/unassigned
  project, subscriber pending/approved/denied/disabled, poll/delivery error,
  retrying, and removal confirmation.
- Unassigned name-only/missing/non-Git/conflicting/ambiguous/stale, attach
  available/blocked/running/failed/complete, and retirement
  planned/blocked/running/partial/complete.
- Bulk selection empty/selected, plan blocked/expired, confirmation, running,
  partial, cancelled, and complete with per-target results.
- Performance collecting, populated, stale, sampler error, and history reset.
- Update current, available, ignored, deferred, rate-limited, offline,
  malformed release, and wrong distribution channel.

## Platform behavior

- Android uses bottom-reachable navigation and never asks for the legacy host
  bearer. Background work follows Android limits; update installation follows
  the exact Play or sideload channel.
- macOS and Windows use a navigation rail/sidebar at wide widths. Verified
  macOS hosts may use the local legacy connection; Windows uses native v2 until
  a separately secured Windows authority exists. Menu-bar/tray features are
  platform adapters, not prerequisites for core correctness.
- Keyboard focus, pointer hover, screen readers, text scaling, reduced motion,
  and high-contrast settings remain usable in every visual style.

## Deferred server capabilities

The UI and typed contracts preserve these independently gated journeys:

| Family | Advertised capability | Inherited behavior that must remain true |
| --- | --- | --- |
| PostgreSQL protection | `databases.read`, `databases.backup`, `databases.restore` | Unavailable discovery is not a database row; backup evidence names the immutable target, checksum and strong restore test; restore uses a fresh reviewed plan, verified incoming backup, new strongly verified safety backup, exact phrase, and retained rollback evidence. |
| Routes | `routes.manage`, optionally `routes.credentials.manage` | Create a fixed-port, managed-server, or container route; private/login is the safe default; going public names the exact host and consequence; resolution failures stay visible; upstream secrets are write-only and responses are redacted. |
| Access | `access.manage` | Configured owners are immutable recovery accounts; invited users receive only exact immutable destination grants; removal revokes live authorization; a reused slug never inherits an old grant. |
| Incoming invites | `invites.manage` | The installed client reads/decides the owner queue; the denied-host flow alone creates a request from verified identity plus a signed, server-derived destination claim. A stale route instance cannot be approved for its replacement. |
| Telegram | `telegram.manage` | Bot token is accepted once and never returned; caller ownership and configured-owner override remain isolated; assignments use exact project ids; webhook takeover is explicit; private-chat subscribers require a separate decision and receive no backlog. |
| Unassigned resources | `unassigned.read`, `unassigned.attach`, `unassigned.retire` | Name resemblance never establishes ownership; attach uses the current immutable/control/ownership fingerprints and one validated repository; standalone retirement is a fresh stop/fence/verify plan that retains files, volumes, databases, backups, and evidence. |
| Bulk stop | `bulk.stop` | Only explicit checked running resources enter a bounded fresh plan; confirmation names the count and consequences; every target keeps its own result, including partial failure. |
| Performance | `performance.read` | Host, server, container, and project CPU/memory are measured samples with timestamps; current/peak/window remain numeric; sampler failure, stale series, and process-local history reset are explicit. |
| Windows authority | no client capability until designed | Privileged host control belongs in a separately secured Windows service; the application never recreates process, Docker, database, or lifecycle authority. |

For every conditional family, all of the following gates must pass before the
client reveals an action:

- `/meta` advertises the exact known capability;
- `/session` contains the required user scope and resource grant;
- the object advertises the exact allowed action with no blocking condition;
- the mutation uses a fresh revision plus an idempotency key; and
- provider, generated-contract, consumer-state, and real end-to-end tests pass.

An absent or unknown capability is ignored safely. It is never approximated
with a legacy host token, a client-side command, guessed ownership, synthetic
metrics, or local-only preferences.
