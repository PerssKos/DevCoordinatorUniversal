## 0.2.0

- Add an independently testable Native Gateway v2 core client for the required
  meta, session, inventory, event, resource action/log, port lease, lifecycle,
  and durable-operation endpoints.
- Add strict v2 DTO parsers with exact known-capability mapping, unknown
  capability omission, session scopes/grants, fail-closed partial inventory,
  and retained operation target results.
- Add HTTPS bearer isolation, public unauthenticated meta exchange, bounded
  JSON transport, strong ETag caching/preconditions, UUID idempotency keys,
  RFC 9457 problem parsing, and inconclusive mutation timeout semantics.
- Keep OAuth/PKCE, the application adapter, optional capability profiles, and
  the native-gateway provider outside this package boundary.
- Verify the exact public legacy service marker before reading its bearer,
  disable redirects on legacy requests, and require full immutable container
  IDs for legacy log reads.
- Match the canonical v1 lifecycle plan/restore field sets and reject action
  responses without affirmative endpoint-appropriate completion evidence.
- Require the exact enrolled server target when requesting a canonical
  broker-backed port lease.
- Treat malformed, oversized, wrong-content-type, or schema-invalid successful
  mutation responses as inconclusive outcomes after dispatch.

## 0.1.0

- Add strict loopback and HTTPS endpoint policies.
- Add typed inventory, event, action, log, port, and lifecycle contracts.
- Add bounded authenticated HTTP transport with credential redaction.
- Reject semantic failures returned with HTTP 200.
- Preserve immutable server targets and fail closed for name-only container
  mutations.
- Distinguish an inconclusive dispatched mutation from an ordinary timeout.
