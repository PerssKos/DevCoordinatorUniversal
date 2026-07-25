## 0.1.0

- Add the pure Dart `GitHubReleaseSource` with conditional `ETag` requests.
- Add strict GitHub payload and semantic-version validation.
- Add serializable release cache and prompt-suppression state.
- Add update, current, downgrade, ignored, and deferred decisions.
- Add typed transport, HTTP, payload, and cache protocol failures.
- Add a 24-hour automatic-check schedule with an explicit manual bypass.
- Require absolute HTTPS release endpoints and links without embedded
  credentials.
