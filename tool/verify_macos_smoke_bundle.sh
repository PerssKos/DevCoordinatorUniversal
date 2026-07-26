#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /path/to/DevCoordinator.app\n' "$0" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'macOS bundle verification must run on macOS.\n' >&2
  exit 1
fi

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd -P
)"
app_root="$repository_root/apps/devcoordinator"
pubspec_path="$app_root/pubspec.yaml"
bundle_parent="$(
  cd "$(dirname "$1")"
  pwd -P
)"
bundle_path="$bundle_parent/$(basename "$1")"

canonical_bundle_id="io.github.holyglory.devcoordinator"
canonical_callback_scheme="io.github.holyglory.devcoordinator"
canonical_callback_name="io.github.holyglory.devcoordinator.oauth"
canonical_repository="PerssKos/DevCoordinatorUniversal"
canonical_gateway="https://console.classified.guru/api/v2"
canonical_minimum_macos="10.15"

for required_tool in \
  /usr/bin/codesign \
  /usr/bin/file \
  /usr/bin/lipo \
  /usr/bin/plutil \
  /usr/bin/strings
do
  if [[ ! -x "$required_tool" ]]; then
    printf 'Required macOS executable is unavailable: %s\n' \
      "$required_tool" >&2
    exit 1
  fi
done

if [[ ! -d "$bundle_path" || -L "$bundle_path" ]]; then
  printf 'Expected a real macOS application bundle directory: %s\n' \
    "$bundle_path" >&2
  exit 1
fi

declared_version="$(
  awk '/^version:[[:space:]]+/ { print $2; exit }' "$pubspec_path"
)"
if [[ ! "$declared_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
  printf 'pubspec version must be SemVer plus a positive build number: %s\n' \
    "$declared_version" >&2
  exit 1
fi
version_name="${declared_version%%+*}"
build_number="${declared_version##*+}"

info_plist="$bundle_path/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  printf 'Application bundle has no Info.plist: %s\n' "$bundle_path" >&2
  exit 1
fi

plist_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$info_plist"
}

actual_bundle_id="$(plist_value CFBundleIdentifier)"
actual_version="$(plist_value CFBundleShortVersionString)"
actual_build_number="$(plist_value CFBundleVersion)"
actual_minimum_macos="$(plist_value LSMinimumSystemVersion)"
actual_callback_name="$(plist_value CFBundleURLTypes.0.CFBundleURLName)"
actual_callback_scheme="$(
  plist_value CFBundleURLTypes.0.CFBundleURLSchemes.0
)"
if [[ "$actual_bundle_id" != "$canonical_bundle_id" \
  || "$actual_version" != "$version_name" \
  || "$actual_build_number" != "$build_number" \
  || "$actual_minimum_macos" != "$canonical_minimum_macos" \
  || "$actual_callback_name" != "$canonical_callback_name" \
  || "$actual_callback_scheme" != "$canonical_callback_scheme" ]]; then
  printf 'Unexpected macOS bundle identity or callback declaration.\n' >&2
  printf 'bundle=%s version=%s build=%s minimum=%s callback=%s/%s\n' \
    "$actual_bundle_id" \
    "$actual_version" \
    "$actual_build_number" \
    "$actual_minimum_macos" \
    "$actual_callback_name" \
    "$actual_callback_scheme" >&2
  exit 1
fi
if /usr/bin/plutil -extract CFBundleURLTypes.1 xml1 -o - "$info_plist" \
  >/dev/null 2>&1 \
  || /usr/bin/plutil \
    -extract CFBundleURLTypes.0.CFBundleURLSchemes.1 \
    raw \
    -o - \
    "$info_plist" >/dev/null 2>&1; then
  printf 'Application bundle must declare one exact OAuth callback scheme.\n' \
    >&2
  exit 1
fi

executable_name="$(plist_value CFBundleExecutable)"
main_executable="$bundle_path/Contents/MacOS/$executable_name"
if [[ ! -f "$main_executable" || ! -x "$main_executable" ]]; then
  printf 'Application bundle has no executable main binary: %s\n' \
    "$main_executable" >&2
  exit 1
fi

require_symlink() {
  local relative_path="$1"
  local expected_target="$2"
  local link_path="$bundle_path/$relative_path"
  if [[ ! -L "$link_path" ]]; then
    printf 'Required framework symlink is missing: %s\n' \
      "$relative_path" >&2
    exit 1
  fi
  local actual_target
  actual_target="$(readlink "$link_path")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    printf 'Unexpected symlink target for %s: %s\n' \
      "$relative_path" "$actual_target" >&2
    exit 1
  fi
}

for framework in App FlutterMacOS objective_c; do
  require_symlink \
    "Contents/Frameworks/$framework.framework/Versions/Current" \
    "A"
  require_symlink \
    "Contents/Frameworks/$framework.framework/$framework" \
    "Versions/Current/$framework"
  require_symlink \
    "Contents/Frameworks/$framework.framework/Resources" \
    "Versions/Current/Resources"
done

symlink_count="$(
  find "$bundle_path" -type l -print | wc -l | tr -d '[:space:]'
)"
if [[ ! "$symlink_count" =~ ^[0-9]+$ ]] || (( symlink_count < 9 )); then
  printf 'Application bundle has too few framework symlinks: %s\n' \
    "$symlink_count" >&2
  exit 1
fi
while IFS= read -r -d '' link_path; do
  link_target="$(readlink "$link_path")"
  if [[ "$link_target" == /* || "$link_target" == ".." \
    || "$link_target" == ../* ]]; then
    printf 'Application bundle contains an unsafe symlink: %s -> %s\n' \
      "$link_path" "$link_target" >&2
    exit 1
  fi
done < <(find "$bundle_path" -type l -print0)

mach_o_count=0
while IFS= read -r -d '' candidate; do
  description="$(/usr/bin/file -b "$candidate")"
  if [[ "$description" != *"Mach-O"* ]]; then
    continue
  fi
  mach_o_count=$((mach_o_count + 1))
  if ! /usr/bin/lipo -verify_arch x86_64 arm64 "$candidate" \
    >/dev/null 2>&1; then
    printf 'Mach-O code is not universal x86_64/arm64: %s\n' \
      "$candidate" >&2
    exit 1
  fi
  architecture_count=0
  has_x86_64=false
  has_arm64=false
  for architecture in $(/usr/bin/lipo -archs "$candidate"); do
    architecture_count=$((architecture_count + 1))
    case "$architecture" in
      x86_64) has_x86_64=true ;;
      arm64) has_arm64=true ;;
      *)
        printf 'Mach-O code has an unexpected architecture %s: %s\n' \
          "$architecture" "$candidate" >&2
        exit 1
        ;;
    esac
  done
  if (( architecture_count != 2 )) \
    || [[ "$has_x86_64" != true || "$has_arm64" != true ]]; then
    printf 'Mach-O code must contain exactly x86_64 and arm64: %s\n' \
      "$candidate" >&2
    exit 1
  fi
done < <(find "$bundle_path" -type f -print0)
if (( mach_o_count < 4 )); then
  printf 'Application bundle contains too few verified Mach-O objects: %s\n' \
    "$mach_o_count" >&2
  exit 1
fi

if ! /usr/bin/codesign \
  --verify \
  --deep \
  --strict \
  --verbose=2 \
  "$bundle_path"; then
  printf 'Ad-hoc macOS bundle signature verification failed.\n' >&2
  exit 1
fi
signature_details="$(
  /usr/bin/codesign --display --verbose=4 "$bundle_path" 2>&1
)"
if ! grep -Fq 'Signature=adhoc' <<<"$signature_details" \
  || ! grep -Fq 'TeamIdentifier=not set' <<<"$signature_details"; then
  printf 'Smoke bundle must use only the expected ad-hoc identity.\n' >&2
  printf '%s\n' "$signature_details" >&2
  exit 1
fi

verification_workspace="$(
  mktemp -d "${TMPDIR:-/tmp}/devcoordinator-macos-verify.XXXXXX"
)"
trap 'rm -rf "$verification_workspace"' EXIT
aot_binary="$bundle_path/Contents/Frameworks/App.framework/App"
aot_strings="$verification_workspace/app.strings"
/usr/bin/strings -a "$aot_binary" >"$aot_strings"
for required_value in "$canonical_repository" "$canonical_gateway"; do
  if ! grep -Fq "$required_value" "$aot_strings"; then
    printf 'Required release value is missing from the macOS app: %s\n' \
      "$required_value" >&2
    exit 1
  fi
done

printf 'Verified ad-hoc macOS smoke bundle: %s\n' "$bundle_path"
