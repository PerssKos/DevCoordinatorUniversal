#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /path/to/release.apk\n' "$0" >&2
  exit 2
fi

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
app_root="$repository_root/apps/devcoordinator"
apk_path="$(realpath -e "$1")"
canonical_repository="PerssKos/DevCoordinatorUniversal"
canonical_gateway="https://console.classified.guru/api/v2"
canonical_package="io.github.holyglory.devcoordinator"
canonical_certificate_sha256="0bbd3187d8e2ea0ee678c57108760cb4078816d90e250ff5dedbe9e632367232"

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
aapt="$build_tools_directory/aapt"
zipalign="$build_tools_directory/zipalign"
apkanalyzer="$(
  find "$android_sdk_root/cmdline-tools" -type f -path '*/bin/apkanalyzer' \
    -perm -111 -print |
    sort -V |
    tail -n 1
)"
python_binary="${PYTHON_BIN:-python3}"
for tool_path in "$apksigner" "$aapt" "$zipalign" "$apkanalyzer"; do
  if [[ -z "$tool_path" || ! -x "$tool_path" ]]; then
    printf 'Required Android executable is unavailable: %s\n' "$tool_path" >&2
    exit 1
  fi
done
if ! command -v "$python_binary" >/dev/null 2>&1; then
  printf 'Required Python executable is unavailable: %s\n' "$python_binary" >&2
  exit 1
fi

declared_version="$(
  awk '/^version:[[:space:]]+/ { print $2; exit }' \
    "$app_root/pubspec.yaml"
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

verification="$("$apksigner" verify --verbose --print-certs "$apk_path")"
printf '%s\n' "$verification"
for required_scheme in \
  'Verified using v2 scheme (APK Signature Scheme v2): true' \
  'Verified using v3 scheme (APK Signature Scheme v3): true'
do
  if ! grep -Fq "$required_scheme" <<<"$verification"; then
    printf 'Required APK signature verification did not pass: %s\n' \
      "$required_scheme" >&2
    exit 1
  fi
done
actual_certificate_sha256="$(
  awk -F': ' \
    '/certificate SHA-256 digest:/ { print tolower($NF); exit }' \
    <<<"$verification"
)"
if [[ "$actual_certificate_sha256" != "$canonical_certificate_sha256" ]]; then
  printf 'Unexpected signing certificate SHA-256: %s\n' \
    "$actual_certificate_sha256" >&2
  exit 1
fi

"$zipalign" -c -P 16 -v 4 "$apk_path" >/dev/null

badging="$("$aapt" dump badging "$apk_path")"
package_line="$(sed -n '1p' <<<"$badging")"
actual_package="$(
  sed -n "s/^package: name='\\([^']*\\)'.*/\\1/p" <<<"$package_line"
)"
actual_version_code="$(
  sed -n "s/.* versionCode='\\([^']*\\)'.*/\\1/p" <<<"$package_line"
)"
actual_version_name="$(
  sed -n "s/.* versionName='\\([^']*\\)'.*/\\1/p" <<<"$package_line"
)"
if [[ "$actual_package" != "$canonical_package" \
  || "$actual_version_code" != "$version_code" \
  || "$actual_version_name" != "$version_name" ]]; then
  printf 'Unexpected APK identity: package=%s versionCode=%s versionName=%s\n' \
    "$actual_package" "$actual_version_code" "$actual_version_name" >&2
  exit 1
fi

"$python_binary" \
  "$repository_root/tool/validate_android_release_manifest.py" \
  --self-test \
  --apk "$apk_path" \
  --apkanalyzer "$apkanalyzer"

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/devcoordinator-apk-check.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
app_strings_file="$staging_directory/libapp.strings"
unzip -p "$apk_path" lib/arm64-v8a/libapp.so |
  strings >"$app_strings_file"
for required_value in "$canonical_repository" "$canonical_gateway"; do
  if ! grep -Fqx "$required_value" "$app_strings_file"; then
    printf 'Required release value is missing from the APK: %s\n' \
      "$required_value" >&2
    exit 1
  fi
done
if grep -Eq \
  'file:///(home|root|Users)/|file:///[A-Za-z]:/(Users|Documents and Settings)/' \
  "$app_strings_file"; then
  printf 'APK contains a private absolute build-workspace URI.\n' >&2
  exit 1
fi

printf 'Verified Android release artifact: %s\n' "$apk_path"
