# Decision History

## Direction

Confirmed user intent: make DevCoordinator a standalone, extensible application
that runs as an installed app on Android, macOS, and Windows; start with a
modern Samsung-inspired visual language; allow other style packs such as
Cupertino; support system, light, and dark appearance; and notify the user when
a repository release is newer. See
[DCU-2026-07-25-01](DecisionDetails/DCU-2026-07-25-01.md),
[DCU-2026-07-25-02](DecisionDetails/DCU-2026-07-25-02.md),
[DCU-2026-07-25-03](DecisionDetails/DCU-2026-07-25-03.md), and
[DCU-2026-07-25-04](DecisionDetails/DCU-2026-07-25-04.md).

Confirmed inherited direction: coordinator state and actions remain real,
attributable, capability-gated, and fail closed; one canonical host authority
owns lifecycle safety; retained history is not discarded for a cleaner UI.
The client presents those server contracts and never recreates authority logic.
See [DCU-2026-07-25-02](DecisionDetails/DCU-2026-07-25-02.md) and
[DCU-2026-07-25-05](DecisionDetails/DCU-2026-07-25-05.md).

## DCU-2026-07-25-01 — Flutter workspace is the cross-platform foundation

ID: DCU-2026-07-25-01 · Details:
[supporting record](DecisionDetails/DCU-2026-07-25-01.md)

Decision: Use a Flutter/Dart Pub workspace with one application and independent
coordinator-client, design-system, and release-update packages. Ship native
Android, macOS, and Windows runners from one shared feature implementation.

Why: Flutter uniquely combines stable Android/macOS/Windows packaging,
machine-code releases, first-party Material and Cupertino libraries, and one
runtime-switchable UI layer. Compose Multiplatform would add JVM desktop and
bespoke Cupertino/update/storage work; React Native splits desktop ownership
across extra projects; Tauri would retain a WebView product. Flutter renders
its own widgets rather than using every operating system's native controls,
which is the necessary tradeoff for one switchable Samsung/Cupertino UI.

## DCU-2026-07-25-02 — Host authority stays server-side

ID: DCU-2026-07-25-02 · Details:
[supporting record](DecisionDetails/DCU-2026-07-25-02.md)

Decision: Keep broker, database, process, Docker, PostgreSQL, access, and
lifecycle safety in DevCoordinator. Support legacy v1 only as a local desktop
connection on its verified macOS host; require a versioned HTTPS native gateway
with user-scoped tokens for Android, Windows, or remote desktop use.

Why: Forking privileged logic would create two authorities; exposing the
loopback host-wide bearer would bypass per-user grants; and a WebView wrapper
would not meet the requested installed adaptive-app experience. A typed,
capability-advertising native gateway preserves one authority and permits safe
mobile expansion.

## DCU-2026-07-25-03 — Style and brightness are orthogonal

ID: DCU-2026-07-25-03 · Details:
[supporting record](DecisionDetails/DCU-2026-07-25-03.md)

Decision: Model visual style as `oneUiInspired`, `cupertino`, or `material`,
and brightness separately as system, light, or dark. Features use semantic
tokens and `App*` components rather than directly selecting Material or
Cupertino widgets.

Why: A single theme toggle cannot add future component languages, while
copying vendor assets creates licensing and maintenance risk. Semantic
components allow a new style renderer without changing domain logic and keep
all styles usable in either brightness.

## DCU-2026-07-25-04 — Releases notify; channels install

ID: DCU-2026-07-25-04 · Details:
[supporting record](DecisionDetails/DCU-2026-07-25-04.md)

Decision: Check the latest non-draft, non-prerelease GitHub release at cold
start, foreground resume, and on manual request; reuse each successful
automatic check for 24 hours, cache ETags, compare SemVer, and prompt with
release notes. Delegate installation to the build's distribution channel
instead of implementing one cross-platform self-installer.

Why: Commit comparison would prompt for unreleased work, embedding a repository
token would leak it, and one downloader would violate Play policy and bypass
macOS/Windows signing and store identity. A provider-neutral release source
plus channel-specific action gives accurate prompts now and leaves Play, Store,
and signed-direct installers independently replaceable.

## DCU-2026-07-25-05 — The legacy bearer is process-session-only

ID: DCU-2026-07-25-05 · Details:
[supporting record](DecisionDetails/DCU-2026-07-25-05.md)

Decision: Keep the legacy loopback bearer only in process memory and persist
only its non-secret host profile. A new process never reads the old durable
credential key; it can only delete it. Retain the cleanup gate for confirmed
legacy-key removal and block new connections while that cleanup is unresolved.

Why: A preferences marker or second secure-store tombstone cannot preserve
disconnect intent when every persistent write fails; aborting disconnect until
the marker is durable would leave a visibly rejected logout eligible for later
automatic reconnect. Session-only storage is the only option that proves an
old host-wide bearer cannot survive process restart. It costs one token entry
per app launch, which is appropriate for the current sensitive local-preview
credential and does not constrain future scoped OAuth session storage.
