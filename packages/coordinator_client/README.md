# coordinator_client

Pure-Dart, typed and fail-closed client contracts for DevCoordinator.

The package deliberately separates two connection modes:

- `LegacyLoopbackV1Client` talks to the existing coordinator only through
  `localhost` or literal `127.0.0.0/8`. It is for a desktop app running on the
  same host as the coordinator.
- `NativeGatewayV2CoreClient` implements the proposed contract's required core
  transport and DTO boundary over HTTPS. `NativeGatewayV2Client` remains the
  future application-facing adapter seam, so the app cannot accidentally treat
  v2 DTOs as legacy host-authority objects or silently downgrade to v1.

It contains no Flutter dependency, privileged lifecycle implementation,
database schema, OAuth flow, token storage, logging, or UI. The v2 provider and
application adapter are not yet implemented; these client primitives do not
claim that a native gateway is deployed.

## Safety properties

- Legacy endpoints reject non-loopback hosts, credentials in URLs, path
  prefixes, queries, and fragments.
- Native-v2 endpoints reject non-HTTPS URLs.
- Native v2 exposes only the contract-defined core methods. There is no public
  arbitrary-path or arbitrary-request-JSON transport.
- `/meta` is public and never asks the access-token provider for a credential.
  Every other core request obtains a fresh bearer from the injected
  `NativeGatewayAccessTokenProvider`. Automatic redirects are disabled so a
  bearer is never forwarded away from the validated HTTPS origin.
- Native responses enforce exact success status, UTF-8 media type, request and
  streamed-response bounds, and whole-request deadlines. RFC 9457
  `application/problem+json` responses become typed
  `NativeGatewayProblemException` values after credential redaction.
- Native meta maps exact known capability identifiers and drops unknown future
  identifiers. Session roles, scopes, and exact-resource grants are typed.
- Fresh inventory requires a strong ETag. Callers may send it back with
  `If-None-Match` and receive a typed `NativeGatewayNotModified`; partial
  inventory fails closed.
- Every core resource, port, and lifecycle mutation accepts typed request
  fields, a strong `If-Match`, and a canonical UUID idempotency key where the
  contract requires them. Dynamic opaque IDs are encoded as one path segment.
- Durable `NativeGatewayOperation` parsing retains target results and errors.
  `isSuccessful` is true only for `succeeded` with neither failure flag, no
  errors, and every target result succeeded. Callers poll by exact operation
  UUID; this package does not invent a polling cadence.
- The legacy v1 bearer is obtained for each request from an injected
  asynchronous `CoordinatorTokenProvider`; neither connection mode retains its
  credential in exceptions or models.
- Before that legacy bearer is read, `readMeta()` performs a bounded,
  no-redirect, unauthenticated `/healthz` preflight and requires the exact
  canonical service marker. This prevents accidental wrong-port disclosure;
  it is not cryptographic peer authentication.
- Request and streamed response bodies are bounded. Inventory has a separate
  larger bound. Requests have operation-class deadlines.
- If a dispatched mutation times out or its transport breaks before a
  conclusive response, it raises
  `CoordinatorMutationOutcomeUnknownException`. The exception retains only
  method, fixed path, and deadline; callers must reconcile authoritative state
  before offering another action. A deadline reached before dispatch prevents
  that request from being sent later.
- Successful responses must be UTF-8 `application/json` objects with
  schema-checked fields.
- HTTP 200 is still failure when an action reports `ok:false`,
  `partial:true`, `needs_attention:true`, `blocked:true`, a
  blocked/failed/partial/incomplete status, or non-empty `action_errors`.
  `CoordinatorSemanticException.response` retains the typed-safe JSON
  evidence for the application result surface.
- An action also needs affirmative endpoint-appropriate completion evidence;
  an empty or unrelated success object is a protocol failure.
- Inventory applies the same top-level fail-closed checks while still accepting
  the ordinary complete v1 snapshot, where `ok` is absent.
- Mutations accept typed project/server/container/lease/lifecycle targets.
  There is no public arbitrary-path or arbitrary-JSON request method.
- Legacy v1 server mutations send the immutable `server_id` alongside
  project/name attribution. Direct container lifecycle is not advertised and
  fails before HTTP because the legacy Docker endpoints accept only a mutable
  name; an exact container mutation requires a future capability-advertising
  gateway. Legacy container logs are read-only and require a full immutable
  64-hex Docker container ID; a name or short ID fails before HTTP.
- Legacy lifecycle plan/restore requests use the canonical exact field sets
  and require a non-empty reason before dispatch.

## Domain snapshot

`readInventory()` parses the normalized inventory plus its explicit
`v1_compatibility` projection into:

- `CoordinatorProject`
- `CoordinatorServer`
- `CoordinatorContainer`
- `CoordinatorLease`
- `CoordinatorEvent`
- `CoordinatorBackup`
- `CoordinatorUnassignedResource`

Normalized immutable IDs win. Compatibility presentation is joined only by an
exact ID; names are never used to infer normalized ownership. Older
compatibility-only inventory is supported as an explicit fallback.

## Usage

```dart
import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;

final gateway = LegacyLoopbackV1Client(
  endpoint: CoordinatorEndpoint.legacyV1(
    Uri.parse('http://127.0.0.1:29876'),
  ),
  tokenProvider: CallbackCoordinatorTokenProvider(
    () async => secureTokenStore.readCoordinatorBearer(),
  ),
  httpClient: http.Client(),
  closeHttpClient: true,
);

final meta = await gateway.readMeta();
if (meta.supports(CoordinatorCapability.inventoryRead)) {
  final inventory = await gateway.readInventory();
  // Render only this real snapshot or an honest loading/error/empty state.
}
```

Server operations require exact typed targets:

```dart
await gateway.actOnServer(
  target: CoordinatorServerTarget(
    id: server.id,
    repoId: server.repoId!,
    projectRoot: server.projectRoot!,
    name: server.name,
  ),
  actor: CoordinatorActor(currentAccountId),
  action: CoordinatorResourceAction.restart,
  reason: 'Restarted from the native app',
);
```

For destructive lifecycle work, first retain and show the returned
`CoordinatorLifecyclePlan`, then apply only its exact ID, fingerprint, and
server-issued confirmation phrase.

The proposed v2 core can be exercised independently of the app adapter:

```dart
final core = NativeGatewayV2CoreClient(
  endpoint: CoordinatorEndpoint.nativeV2(
    Uri.parse('https://gateway.example.test/api/v2'),
  ),
  accessTokenProvider: CallbackNativeGatewayAccessTokenProvider(
    () async => installedClientSession.readShortLivedAccessToken(),
  ),
  httpClient: http.Client(),
  closeHttpClient: true,
);

// Public: no access token is read or sent.
final meta = await core.readMeta();

// Authenticated and conditional.
final inventoryResult = await core.readInventory();
if (inventoryResult case NativeGatewayModified(
  :final value,
  :final entityTag,
)) {
  final operation = await core.actOnResource(
    resourceId: value.resources.single.id,
    action: NativeGatewayResourceAction.restart,
    request: NativeGatewayActionRequest(reason: 'Operator approved'),
    ifMatch: entityTag,
    idempotencyKey: NativeGatewayIdempotencyKey.generate(),
  );
  // Retain the operation, then poll operation.id through readOperation().
}
```

The token callback above is an integration seam, not an OAuth implementation.
The application must supply a short-lived user/device access token from the
future approved Authorization Code + PKCE flow; it must never supply the
loopback coordinator bearer.

## Tests

The unit suite uses `package:http/testing.dart` `MockClient` and covers endpoint
policy, public/authenticated request separation, credential
injection/redaction, ETag/304 behavior, RFC 9457 failures, mutation
preconditions/idempotency, timeout outcome semantics, request/response bounds,
strict v1 and v2 JSON, normalized/compatibility parsing, opaque cursors, every
supported core action family, lifecycle plan binding, durable operations, and
typed-target validation.
