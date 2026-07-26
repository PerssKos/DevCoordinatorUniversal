#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: %s /path/to/DevCoordinator.app [output-directory]\n' \
    "$0" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'macOS smoke packaging must run on macOS.\n' >&2
  exit 1
fi

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd -P
)"
app_root="$repository_root/apps/devcoordinator"
bundle_parent="$(
  cd "$(dirname "$1")"
  pwd -P
)"
bundle_path="$bundle_parent/$(basename "$1")"
output_directory="$(
  if [[ $# -eq 2 ]]; then
    install -d -m 755 "$2"
    cd "$2"
  else
    install -d -m 755 "$app_root/build/smoke/macos"
    cd "$app_root/build/smoke/macos"
  fi
  pwd -P
)"

for required_tool in /usr/bin/ditto /usr/bin/shasum; do
  if [[ ! -x "$required_tool" ]]; then
    printf 'Required macOS executable is unavailable: %s\n' \
      "$required_tool" >&2
    exit 1
  fi
done

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

"$repository_root/tool/verify_macos_smoke_bundle.sh" "$bundle_path"

packaging_workspace="$(
  mktemp -d "${TMPDIR:-/tmp}/devcoordinator-macos-package.XXXXXX"
)"
trap 'rm -rf "$packaging_workspace"' EXIT
archive_name="DevCoordinator-$version_name-macos-universal-adhoc-smoke.zip"
archive_path="$packaging_workspace/$archive_name"
checksum_path="$packaging_workspace/$archive_name.sha256"
extraction_root="$packaging_workspace/extracted"
install -d -m 755 "$extraction_root"

/usr/bin/ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$bundle_path" \
  "$archive_path"
if [[ ! -s "$archive_path" ]]; then
  printf 'ditto did not produce a non-empty macOS smoke archive.\n' >&2
  exit 1
fi

(
  cd "$packaging_workspace"
  /usr/bin/shasum -a 256 "$archive_name" >"$archive_name.sha256"
  /usr/bin/shasum -a 256 -c "$archive_name.sha256"
)

/usr/bin/ditto -x -k "$archive_path" "$extraction_root"
extracted_bundle="$extraction_root/$(basename "$bundle_path")"
top_level_count="$(
  find "$extraction_root" -mindepth 1 -maxdepth 1 -print |
    wc -l |
    tr -d '[:space:]'
)"
if [[ "$top_level_count" != 1 || ! -d "$extracted_bundle" ]]; then
  printf 'Archive must contain exactly one top-level application bundle.\n' \
    >&2
  exit 1
fi

write_symlink_manifest() {
  local application_bundle="$1"
  local destination="$2"
  (
    cd "$application_bundle"
    while IFS= read -r link_path; do
      printf '%s\t%s\n' "$link_path" "$(readlink "$link_path")"
    done < <(find . -type l -print | LC_ALL=C sort)
  ) >"$destination"
}

source_links="$packaging_workspace/source-links.txt"
extracted_links="$packaging_workspace/extracted-links.txt"
write_symlink_manifest "$bundle_path" "$source_links"
write_symlink_manifest "$extracted_bundle" "$extracted_links"
if ! cmp -s "$source_links" "$extracted_links"; then
  printf 'Archive round-trip changed macOS bundle symlinks.\n' >&2
  diff -u "$source_links" "$extracted_links" >&2 || true
  exit 1
fi

"$repository_root/tool/verify_macos_smoke_bundle.sh" "$extracted_bundle"

install -m 644 "$archive_path" "$output_directory/$archive_name"
install -m 644 "$checksum_path" \
  "$output_directory/$archive_name.sha256"
(
  cd "$output_directory"
  /usr/bin/shasum -a 256 -c "$archive_name.sha256"
)

printf 'Ad-hoc macOS smoke ZIP: %s\n' \
  "$output_directory/$archive_name"
printf 'SHA-256: '
cut -d ' ' -f 1 "$output_directory/$archive_name.sha256"
