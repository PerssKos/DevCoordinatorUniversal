# Release operations

1. Update `apps/devcoordinator/pubspec.yaml` with the next SemVer and monotonic
   build number.
2. Run workspace format, analyze, unit/widget tests, and target-host build
   smoke gates.
3. Build each distribution channel with its stable application identity.
   Every build must include
   `--dart-define=UPDATE_REPOSITORY=<canonical-owner>/<canonical-repository>`;
   CI derives this from `github.repository`. Set
   `UPDATE_DISTRIBUTION_CHANNEL` to `direct`, `play`, `mac_app_store`, or
   `microsoft_store`; omission means `direct`. Direct builds must not set a
   destination. Store builds must set the exact official
   `UPDATE_DESTINATION_URL`; Mac App Store and Microsoft Store builds must also
   set `UPDATE_STORE_PRODUCT_ID` to the identity assigned in App Store Connect
   or Partner Center.
4. Sign Android, macOS, and Windows artifacts with the configured production
   identities. Notarize and staple direct macOS packages.
5. Produce checksums, verify them from a clean download, and create a GitHub
   release tagged `v<version>`. Direct assets use the exact platform names
   `DevCoordinator-<version>-android.apk`,
   `DevCoordinator-<version>-macos.dmg`, and
   `DevCoordinator-<version>-windows.msix`; smoke artifacts never use these
   names. For a Store release, wait until the exact version is visible in that
   Store, then upload one non-empty marker named
   `DevCoordinator-<version>-android-google-play-io.github.holyglory.devcoordinator.release.json`,
   `DevCoordinator-<version>-macos-mac-app-store-<apple-app-id>.release.json`,
   or
   `DevCoordinator-<version>-windows-microsoft-store-<microsoft-store-id>.release.json`.
   The ID in the marker must equal the build-pinned listing identity. The
   marker is compatibility evidence, not an installer or a substitute for
   Store publication.
6. Confirm the previous production app discovers the release and routes the
   update action to the correct channel.
7. Install over the previous version on each platform and verify preferences,
   session-only legacy credential behavior, future channel-specific secure
   credentials, connection state, and rollback/recovery behavior.

CI compiles Android debug and unsigned-release smokes but never uploads them,
because a debug package must not compete for the production OAuth callback.
It retains a clearly labeled ad-hoc macOS target-smoke ZIP with its SHA-256
checksum and a self-signed Windows target-smoke artifact for seven days. The
macOS job uses `ditto` so framework symlinks and bundle metadata survive the
artifact round trip, then repeats bundle identity, callback, architecture,
embedded endpoint/update source, and ad-hoc signature verification against the
extracted app. These are diagnostics, not production installers, and must
never be attached to or relabeled as a stable signed release.

## Direct Android release

`tool/build_android_release.sh` is the canonical direct-APK builder. It refuses
to produce a release unless Git is clean, locked dependencies resolve, Android
release lint passes, private inputs are owner-only and outside the repository,
the v2/v3 signature verifies, and the signer is the exact certificate recorded
in `DCU-2026-07-26-08`. It builds from a temporary archive of the committed
source, strips source diagnostics into a private symbol archive, and checks the
production package, monotonically increasing Android build number, exact
merged OAuth callback, fixed gateway, canonical update repository, and absence
of private build-workspace URIs before writing the APK and checksum under
`apps/devcoordinator/build/release/`.

Supply these values only from a private release environment:

```bash
export ANDROID_RELEASE_KEYSTORE=/private/path/devcoordinator-direct.p12
export ANDROID_RELEASE_STORE_PASSWORD_FILE=/private/path/store-password
export ANDROID_RELEASE_KEY_PASSWORD_FILE=/private/path/key-password
export ANDROID_RELEASE_KEY_ALIAS=devcoordinator-direct
export ANDROID_SDK_ROOT=/path/to/android-sdk
export FLUTTER_BIN=/path/to/flutter
tool/build_android_release.sh
```

The keystore and password files must never enter Git, workflow logs, build
artifacts, or a GitHub Release. Preserve an offline owner-controlled backup:
losing the key prevents updates to direct installations, while replacing it
requires uninstalling the existing package.

If an earlier `io.github.holyglory.devcoordinator.debug` test package is
installed, remove it once before installing the production APK. Debug APKs are
not distributed because a second package registered for the production
callback makes Android callback selection ambiguous.

Do not upload the direct-distribution key or passwords to GitHub secrets. From
the clean, already-pushed `main` commit, create and push the exact
`v<SemVer>` tag, export the private builder inputs shown above, and run:

```bash
tool/publish_android_release.sh
```

The local publisher invokes the canonical builder, uploads only the signed APK
plus checksum to a draft, downloads both again, revalidates checksum/signature/
package/merged callback/content, publishes the verified draft, and confirms
anonymous latest-release discovery. A rerun safely reuses a draft or
revalidates an already published release. Read-only GitHub Actions then repeats
source, public-artifact, and update-discovery checks without access to the
private signing identity.
