#!/usr/bin/env bash
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
workspace_app_root="$repository_root/apps/devcoordinator"
pubspec_path="$workspace_app_root/pubspec.yaml"
canonical_repository="PerssKos/DevCoordinatorUniversal"

: "${ANDROID_RELEASE_KEYSTORE:?Set ANDROID_RELEASE_KEYSTORE to the private PKCS12/JKS keystore path.}"
: "${ANDROID_RELEASE_STORE_PASSWORD_FILE:?Set ANDROID_RELEASE_STORE_PASSWORD_FILE to an owner-only password file.}"
: "${ANDROID_RELEASE_KEY_PASSWORD_FILE:?Set ANDROID_RELEASE_KEY_PASSWORD_FILE to an owner-only password file.}"
: "${ANDROID_RELEASE_KEY_ALIAS:?Set ANDROID_RELEASE_KEY_ALIAS to the release key alias.}"

for private_file in \
  "$ANDROID_RELEASE_KEYSTORE" \
  "$ANDROID_RELEASE_STORE_PASSWORD_FILE" \
  "$ANDROID_RELEASE_KEY_PASSWORD_FILE"
do
  if [[ ! -f "$private_file" ]]; then
    printf 'Required private file does not exist: %s\n' "$private_file" >&2
    exit 1
  fi
  resolved_private_file="$(realpath -e "$private_file")"
  if [[ "$resolved_private_file" == "$repository_root" \
    || "$resolved_private_file" == "$repository_root/"* ]]; then
    printf 'Private release input must remain outside the repository: %s\n' \
      "$private_file" >&2
    exit 1
  fi
  private_mode="$(stat -c '%a' "$resolved_private_file")"
  if (( (8#$private_mode & 077) != 0 )); then
    printf 'Private release input must not be group/world accessible: %s\n' \
      "$private_file" >&2
    exit 1
  fi
  if [[ "$(stat -c '%u' "$resolved_private_file")" != "$(id -u)" ]]; then
    printf 'Private release input must be owned by the release user: %s\n' \
      "$private_file" >&2
    exit 1
  fi
done

flutter_binary="${FLUTTER_BIN:-flutter}"
android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$android_sdk_root" || ! -d "$android_sdk_root/build-tools" ]]; then
  printf 'Set ANDROID_SDK_ROOT to an Android SDK with build-tools.\n' >&2
  exit 1
fi

build_tools_directory="$(
  find "$android_sdk_root/build-tools" -mindepth 1 -maxdepth 1 -type d \
    -printf '%f\t%p\n' |
    sort -V |
    tail -n 1 |
    cut -f 2-
)"
apksigner="$build_tools_directory/apksigner"
for tool_path in "$flutter_binary" "$apksigner"; do
  if [[ ! -x "$tool_path" ]] && ! command -v "$tool_path" >/dev/null 2>&1; then
    printf 'Required executable is unavailable: %s\n' "$tool_path" >&2
    exit 1
  fi
done

declared_version="$(
  awk '/^version:[[:space:]]+/ { print $2; exit }' "$pubspec_path"
)"
if [[ ! "$declared_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
  printf 'pubspec version must be SemVer plus a positive build number: %s\n' \
    "$declared_version" >&2
  exit 1
fi
version_name="${declared_version%%+*}"
version_code="${declared_version##*+}"
if (( ${#version_code} > 10 || 10#$version_code > 2100000000 )); then
  printf 'Android versionCode is outside the supported range: %s\n' \
    "$version_code" >&2
  exit 1
fi

maximum_previous_version_code=0
if git -C "$repository_root" rev-parse --is-inside-work-tree \
  >/dev/null 2>&1; then
  while IFS= read -r tag; do
    [[ -z "$tag" || "$tag" == "v$version_name" ]] && continue
    if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      continue
    fi
    tagged_version="$(
      git -C "$repository_root" show \
        "$tag:apps/devcoordinator/pubspec.yaml" 2>/dev/null |
        awk '/^version:[[:space:]]+/ { print $2; exit }'
    )"
    if [[ ! "$tagged_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
      printf 'Prior release tag has no valid Android build number: %s\n' \
        "$tag" >&2
      exit 1
    fi
    tagged_version_code="${tagged_version##*+}"
    if (( ${#tagged_version_code} > 10 \
      || 10#$tagged_version_code > 2100000000 )); then
      printf 'Prior release tag has an invalid Android versionCode: %s\n' \
        "$tag" >&2
      exit 1
    fi
    if (( 10#$tagged_version_code > maximum_previous_version_code )); then
      maximum_previous_version_code=$((10#$tagged_version_code))
    fi
  done < <(git -C "$repository_root" tag --list 'v*.*.*')
fi
if (( 10#$version_code <= maximum_previous_version_code )); then
  printf 'Android versionCode %s must exceed prior release maximum %s.\n' \
    "$version_code" "$maximum_previous_version_code" >&2
  exit 1
fi

if [[ -n "$(git -C "$repository_root" status --porcelain --untracked-files=all)" ]]; then
  printf 'Release builds require a clean Git worktree.\n' >&2
  exit 1
fi

release_workspace="$(
  mktemp -d "${TMPDIR:-/tmp}/devcoordinator-release-build.XXXXXX"
)"
trap 'rm -rf "$release_workspace"' EXIT
source_root="$release_workspace/source"
install -d -m 755 "$source_root"
git -C "$repository_root" archive --format=tar HEAD |
  tar -xf - -C "$source_root"
source_app_root="$source_root/apps/devcoordinator"
symbols_directory="$release_workspace/symbols"

(
  cd "$source_app_root"
  "$flutter_binary" pub get --enforce-lockfile
  "$flutter_binary" build apk \
    --release \
    --no-pub \
    "--split-debug-info=$symbols_directory" \
    "--dart-define=UPDATE_REPOSITORY=$canonical_repository"
  android/gradlew -p android :app:lintRelease
)

unsigned_apk="$source_app_root/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$unsigned_apk" ]]; then
  printf 'Flutter did not produce the expected release APK: %s\n' \
    "$unsigned_apk" >&2
  exit 1
fi

signed_apk="$release_workspace/DevCoordinator-$version_name-android.apk"

"$apksigner" sign \
  --ks "$ANDROID_RELEASE_KEYSTORE" \
  --ks-key-alias "$ANDROID_RELEASE_KEY_ALIAS" \
  --ks-pass "file:$ANDROID_RELEASE_STORE_PASSWORD_FILE" \
  --key-pass "file:$ANDROID_RELEASE_KEY_PASSWORD_FILE" \
  --out "$signed_apk" \
  "$unsigned_apk"

ANDROID_SDK_ROOT="$android_sdk_root" \
  "$repository_root/tool/verify_android_release_artifact.sh" "$signed_apk"

output_directory="$workspace_app_root/build/release"
output_apk="$output_directory/DevCoordinator-$version_name-android.apk"
install -d -m 755 "$output_directory"
install -m 644 "$signed_apk" "$output_apk"
(
  cd "$output_directory"
  sha256sum "$(basename "$output_apk")" \
    >"$(basename "$output_apk").sha256"
)
chmod 644 "$output_apk.sha256"
private_output_directory="$workspace_app_root/build/release-private"
symbols_archive="$release_workspace/DevCoordinator-$version_name-android-symbols.tar.gz"
tar -czf "$symbols_archive" -C "$symbols_directory" .
install -d -m 700 "$private_output_directory"
install -m 600 "$symbols_archive" \
  "$private_output_directory/$(basename "$symbols_archive")"

printf 'Release APK: %s\n' "$output_apk"
printf 'SHA-256: '
cut -d ' ' -f 1 "$output_apk.sha256"
