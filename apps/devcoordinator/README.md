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
  --dart-define=UPDATE_REPOSITORY=owner/repository \
  --dart-define=UPDATE_DISTRIBUTION_CHANNEL=direct
```

`UPDATE_DISTRIBUTION_CHANNEL` may be `direct`, `play`, `mac_app_store`, or
`microsoft_store` and must match the target platform. Direct channels reject
`UPDATE_DESTINATION_URL` and accept/open only the exact canonical installer in
the configured repository release. Store channels require an exact
repository-owned version/platform/channel/product-identity marker and one official
`UPDATE_DESTINATION_URL`: the fixed package listing for Play, or the matching
App Store/Microsoft Store product listing together with its
`UPDATE_STORE_PRODUCT_ID`.

## Install and connect on Android

Install only the production-signed direct-release artifact:

`build/release/DevCoordinator-0.2.1-android.apk`

Do not distribute or install `app-debug.apk`; debug builds are compile/test
inputs, not user artifacts. If the earlier `.debug` package is already
installed, uninstall that old test app once before installing the signed APK
so Android has only one handler for the production OAuth callback.

After installation, tap the single connect action. The app uses
`https://console.classified.guru/api/v2`, opens the system browser for Google
sign-in, and returns through the exact application callback. Do not enter a
hostname, coordinator token, URL, or “local desktop” value on Android.

## Connection availability

Android, Windows, and off-host macOS use the HTTPS native gateway. Only the
macOS app running on the verified coordinator host may additionally select the
legacy `Local desktop` preview.

The local macOS host token is process-session-only. The app persists the
non-secret host form values as a convenience, but it never writes the bearer
to disk and requires it again after a new app process starts.
