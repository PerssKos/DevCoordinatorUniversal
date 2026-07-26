## 0.2.0

- Add typed release assets plus backward-compatible, fail-closed cache
  decoding.
- Add bounded stable-release catalogs with independent ETags and
  provider-neutral catalog selection primitives.
- Apply one SemVer 2.0 precedence comparator that ignores build metadata and
  reject ambiguous equal-precedence releases.
- Stream and bound provider payloads, validate source/cache-specific catalog
  limits, and isolate malformed release/asset entries without making a
  matching target eligible.

## 0.1.0

- Add the pure Dart `GitHubReleaseSource` with conditional `ETag` requests.
- Add strict GitHub payload and semantic-version validation.
- Add serializable release cache and prompt-suppression state.
- Add update, current, downgrade, ignored, and deferred decisions.
- Add typed transport, HTTP, payload, and cache protocol failures.
- Add a 24-hour automatic-check schedule with an explicit manual bypass.
- Require absolute HTTPS release endpoints and links without embedded
  credentials.
