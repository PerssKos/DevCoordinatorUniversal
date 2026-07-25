# Release operations

1. Update `apps/devcoordinator/pubspec.yaml` with the next SemVer and monotonic
   build number.
2. Run workspace format, analyze, unit/widget tests, and target-host build
   smoke gates.
3. Build each distribution channel with its stable application identity.
   Every build must include
   `--dart-define=UPDATE_REPOSITORY=<canonical-owner>/<canonical-repository>`;
   CI derives this from `github.repository`. If a channel needs a separate
   landing page, set `UPDATE_DESTINATION_URL` to an absolute HTTPS URL.
4. Sign Android, macOS, and Windows artifacts with the configured production
   identities. Notarize and staple direct macOS packages.
5. Produce checksums, verify them from a clean download, and create a GitHub
   release tagged `v<version>`.
6. Confirm the previous production app discovers the release and routes the
   update action to the correct channel.
7. Install over the previous version on each platform and verify preferences,
   session-only legacy credential behavior, future channel-specific secure
   credentials, connection state, and rollback/recovery behavior.

CI build outputs are ephemeral diagnostics and are not uploaded. They must
never be relabeled as signed production packages.
