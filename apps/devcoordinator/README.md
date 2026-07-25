# DevCoordinator application

The installed Flutter client for Android, macOS, and Windows. Feature and
platform code is composed here; reusable transport, design, and update policy
live in workspace packages.

## Run locally

From the repository root:

```bash
flutter pub get
cd apps/devcoordinator
flutter run -d <device>
```

Local builds do not guess a release source. Supply the canonical public
repository explicitly when update checks are needed:

```bash
flutter run -d <device> \
  --dart-define=UPDATE_REPOSITORY=owner/repository
```

An optional `UPDATE_DESTINATION_URL` must be an absolute HTTPS URL without
embedded credentials.

## Connection availability

The current server contract is a host-wide loopback API, so only the macOS app
running on the verified coordinator host may select `Local desktop`. Android,
Windows, and off-host clients show the native-gateway requirement and never
ask for that bearer. They become operational after the server-owned `/api/v2`
gateway and installed-client sign-in recorded in the root completion ledger
are deployed.

The local macOS host token is process-session-only. The app persists the
non-secret host form values as a convenience, but it never writes the bearer
to disk and requires it again after a new app process starts.
