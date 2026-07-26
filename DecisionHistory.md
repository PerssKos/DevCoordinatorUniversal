# Decision History

## Direction

Confirmed user intent: make DevCoordinator a standalone, extensible application
that runs as an installed app on Android, macOS, and Windows; start with a
modern Samsung-inspired visual language; allow other style packs such as
Cupertino; support system, light, and dark appearance; and notify the user when
a release in the canonical public `PerssKos/DevCoordinatorUniversal`
repository is newer. See
[DCU-2026-07-25-01](DecisionDetails/DCU-2026-07-25-01.md),
[DCU-2026-07-25-02](DecisionDetails/DCU-2026-07-25-02.md),
[DCU-2026-07-25-03](DecisionDetails/DCU-2026-07-25-03.md), and
[DCU-2026-07-25-04](DecisionDetails/DCU-2026-07-25-04.md). Update discovery
is specific to the installed platform and distribution channel; an
Android-only release is not a macOS or Windows update. See
[DCU-2026-07-26-10](DecisionDetails/DCU-2026-07-26-10.md). The production
remote connection is one action against
`https://console.classified.guru/api/v2`, not a hostname, host bearer, or
“local desktop” setup journey. See
[DCU-2026-07-26-07](DecisionDetails/DCU-2026-07-26-07.md).
Direct Android APK distribution uses one dedicated long-lived signing
certificate rather than an ephemeral debug key; Apple and Windows packages
still require their platform-trusted publisher identities. See
[DCU-2026-07-26-08](DecisionDetails/DCU-2026-07-26-08.md). That private
Android key remains on an owner-controlled signer; GitHub receives only the
already-signed APK and independently verifies its public identity. See
[DCU-2026-07-26-09](DecisionDetails/DCU-2026-07-26-09.md).

Confirmed inherited direction: coordinator state and actions remain real,
attributable, capability-gated, and fail closed; one canonical host authority
owns lifecycle safety; retained history is not discarded for a cleaner UI.
The client presents those server contracts and never recreates authority logic.
See [DCU-2026-07-25-02](DecisionDetails/DCU-2026-07-25-02.md) and
[DCU-2026-07-25-05](DecisionDetails/DCU-2026-07-25-05.md). Installed remote
clients discover a same-origin OAuth issuer, use system-browser Authorization
Code + PKCE S256, retain only a rotating refresh credential in platform secure
storage, and act only through immutable IDs and current scopes. The client
renders only server-advertised, canonically implemented capabilities; deferred
lifecycle management stays hidden, exact requested port ranges pass through,
and lease release depends on the server's device-session ownership result. See
[DCU-2026-07-26-06](DecisionDetails/DCU-2026-07-26-06.md) and
[DCU-2026-07-26-07](DecisionDetails/DCU-2026-07-26-07.md).

## DCU-2026-07-26-10 — Update discovery selects a compatible release target

ID: DCU-2026-07-26-10 · Details:
[supporting record](DecisionDetails/DCU-2026-07-26-10.md)

Decision: Supersede the latest-release-only discovery portion of
DCU-2026-07-25-04 with a bounded, ETag-cached catalog of stable releases.
Direct builds select the highest newer SemVer that contains one exact,
non-empty, canonical-repository asset for their compile-time platform and
channel; Store builds additionally require an exact owned publication marker
for that platform/channel/product identity plus an official listing URL tied
to the same build-pinned Store identity. Direct builds open the verified
installer itself and reject a destination override. A newer incompatible
release is silent during automatic checks and is explained during a manual
check.

Why: Reading only the newest repository release could offer an Android APK to
macOS or Windows, while filtering only that release could hide an older but
still newer compatible desktop package. Requiring every release to ship every
platform would block safe independent Android delivery on unavailable Apple
or Windows publisher identities; trusting arbitrary filenames or redirects
would weaken repository and channel ownership. Treating any stable repository
release as proof of Store publication was also rejected because an
Android-direct release says nothing about Apple or Microsoft availability.
Bounded catalog selection with exact owned assets preserves independent
release cadence, truthful prompts, and channel-specific installation.

## DCU-2026-07-26-09 — Stable Android releases are signed off GitHub

ID: DCU-2026-07-26-09 · Details:
[supporting record](DecisionDetails/DCU-2026-07-26-09.md)

Decision: Keep the long-lived direct Android private key and its passwords off
GitHub. Build, lint, sign, and verify on an owner-controlled release host;
stage only the signed APK and checksum as a GitHub draft; download and verify
them again before publication. Let read-only GitHub Actions validate the public
certificate, package, manifest, content, checksum, source tag, and update
discovery after publication.

Why: GitHub Environment secrets would automate signing but copy the durable
update identity into a cloud-runner trust boundary; an improvised manual upload
would keep the key local but make repeatability, failure recovery, and
verification operator-dependent; and publishing an unsigned artifact would
break update identity. An offline scripted signer plus transactional draft
publication preserves the narrowest private-key boundary while retaining a
repeatable and independently audited GitHub release lifecycle.

## DCU-2026-07-26-08 — Direct Android updates keep one signing identity

ID: DCU-2026-07-26-08 · Details:
[supporting record](DecisionDetails/DCU-2026-07-26-08.md)

Decision: Sign direct-distribution production APKs for
`io.github.holyglory.devcoordinator` with one dedicated, privately retained
`PerssKos DevCoordinator Universal` certificate. Never publish the keystore or
password, never use a runner-generated debug identity for a stable release,
and require the exact certificate fingerprint in the release verification
gate. Keep Play App Signing, Apple Developer ID/App Store, and Windows
Store/trusted code-signing identities as distinct distribution-channel
credentials.

Why: An Android debug key differs across workstations and CI runners, so it
cannot provide reliable install-over updates; postponing every usable APK until
all three store identities exist would unnecessarily block direct Android
distribution; and one improvised cross-platform certificate cannot satisfy
Apple or Windows trust. A durable Android direct-distribution key gives the
current APK a stable upgrade identity without conflating it with future store
or desktop publisher credentials.

## DCU-2026-07-26-07 — Production connection, updates, and capabilities are explicit

ID: DCU-2026-07-26-07 · Details:
[supporting record](DecisionDetails/DCU-2026-07-26-07.md)

Decision: Make `https://console.classified.guru/api/v2` the fixed production
remote gateway and make `PerssKos/DevCoordinatorUniversal` the canonical public
release/update repository. Android presents one connect action with no
hostname, host bearer, or local-desktop choice; Windows and remote macOS use the
same native flow, while the legacy loopback preview remains separately limited
to verified local macOS use. Render actions only for capabilities the gateway
currently advertises: keep `lifecycle.manage` hidden while its canonical
durable plan/fingerprint/apply contract is deferred, preserve the user's exact
port range, and permit release only when the server marks that lease releasable
for the current device session.

Why: Generic host setup exposed implementation details and led Android users
to enter values that the production flow does not need; repository guessing
can silently check the wrong release stream; and rendering controls from the
client's known DTO set would overstate unfinished server behavior. One fixed
production gateway and release identity make installation predictable, while
server-advertised capabilities and ownership keep the cross-platform client a
truthful presentation of the canonical authority rather than a competing one.

## DCU-2026-07-26-06 — Remote sessions use system-browser PKCE and secure refresh rotation

ID: DCU-2026-07-26-06 · Details:
[supporting record](DecisionDetails/DCU-2026-07-26-06.md)

Decision: Discover OAuth metadata from the selected HTTPS native gateway,
require same-origin authorization/token/revocation endpoints and PKCE S256,
launch the operating system browser with a fresh verifier and state, accept
only the exact reverse-domain callback, and exchange the code without a client
secret. Keep access tokens in memory; persist the rotating refresh token only
through platform secure storage; resume non-interactively when possible; and
revoke the device family on disconnect. Drive every visible action from the
gateway's capabilities, scopes, grants, immutable IDs, allowed actions, and
strong inventory ETag.

Why: A pasted host bearer would over-authorize the phone, an embedded client
secret is extractable, a WebView-only session would not share the user's
trusted browser context, and trusting arbitrary discovery URLs could leak a
code or refresh token. System-browser PKCE plus same-origin discovery and
platform credential storage satisfies Android, macOS, and Windows without
turning the Flutter client into a second authority.

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
