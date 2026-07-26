#!/usr/bin/env bash
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
canonical_repository="PerssKos/DevCoordinatorUniversal"
pubspec_path="$repository_root/apps/devcoordinator/pubspec.yaml"

if [[ -n "$(git -C "$repository_root" status --porcelain --untracked-files=all)" ]]; then
  printf 'Release publication requires a clean Git worktree.\n' >&2
  exit 1
fi
if [[ "$(gh api user --jq .login)" != PerssKos ]]; then
  printf 'GitHub CLI must be authenticated as PerssKos.\n' >&2
  exit 1
fi
repository_metadata="$(
  gh repo view "$canonical_repository" --json isPrivate,nameWithOwner
)"
if [[ "$(jq -r '.nameWithOwner' <<<"$repository_metadata")" \
    != "$canonical_repository" \
  || "$(jq -r '.isPrivate' <<<"$repository_metadata")" != false ]]; then
  printf 'Canonical public GitHub repository is unavailable.\n' >&2
  exit 1
fi

declared_version="$(
  awk '/^version:[[:space:]]+/ { print $2; exit }' "$pubspec_path"
)"
if [[ ! "$declared_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
  printf 'Invalid application release version: %s\n' "$declared_version" >&2
  exit 1
fi
version_name="${declared_version%%+*}"
release_tag="v$version_name"
head_commit="$(git -C "$repository_root" rev-parse HEAD)"

git -C "$repository_root" fetch --no-tags origin main
if [[ "$(git -C "$repository_root" rev-parse origin/main)" != "$head_commit" ]]; then
  printf 'Release commit must already be the exact origin/main commit.\n' >&2
  exit 1
fi
if ! git -C "$repository_root" rev-parse --verify \
  "$release_tag^{commit}" >/dev/null 2>&1; then
  printf 'Create and push the exact %s tag before publishing.\n' \
    "$release_tag" >&2
  exit 1
fi
if [[ "$(git -C "$repository_root" rev-parse "$release_tag^{commit}")" \
  != "$head_commit" ]]; then
  printf 'Release tag does not identify the current commit.\n' >&2
  exit 1
fi
remote_tag_commit="$(
  git -C "$repository_root" ls-remote origin "refs/tags/$release_tag^{}" |
    awk 'NR == 1 { print $1 }'
)"
if [[ -z "$remote_tag_commit" ]]; then
  remote_tag_commit="$(
    git -C "$repository_root" ls-remote origin "refs/tags/$release_tag" |
      awk 'NR == 1 { print $1 }'
  )"
fi
if [[ "$remote_tag_commit" != "$head_commit" ]]; then
  printf 'Remote release tag does not identify the current commit.\n' >&2
  exit 1
fi

"$repository_root/tool/build_android_release.sh"

apk_name="DevCoordinator-$version_name-android.apk"
checksum_name="$apk_name.sha256"
apk_path="$repository_root/apps/devcoordinator/build/release/$apk_name"
checksum_path="$repository_root/apps/devcoordinator/build/release/$checksum_name"
release_endpoint="repos/$canonical_repository/releases/tags/$release_tag"
error_file="$(mktemp)"
download_directory="$(
  mktemp -d "${TMPDIR:-/tmp}/devcoordinator-release-download.XXXXXX"
)"
trap 'rm -f "$error_file"; rm -rf "$download_directory"' EXIT

if existing="$(gh api "$release_endpoint" 2>"$error_file")"; then
  draft="$(jq -r '.draft' <<<"$existing")"
  if [[ "$draft" != true && "$draft" != false ]]; then
    printf 'Existing release returned an invalid draft state.\n' >&2
    exit 1
  fi
elif grep -Fq '(HTTP 404)' "$error_file"; then
  gh release create "$release_tag" \
    --repo "$canonical_repository" \
    --draft \
    --generate-notes \
    --title "DevCoordinator $version_name" \
    --verify-tag
  draft=true
else
  cat "$error_file" >&2
  exit 1
fi

if [[ "$draft" == true ]]; then
  gh release upload "$release_tag" \
    --repo "$canonical_repository" \
    "$apk_path" \
    "$checksum_path" \
    --clobber
fi

gh release download "$release_tag" \
  --repo "$canonical_repository" \
  --dir "$download_directory" \
  --pattern "$apk_name" \
  --pattern "$checksum_name"
read -r expected_hash expected_name unexpected \
  <"$download_directory/$checksum_name"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ \
  || "$expected_name" != "$apk_name" \
  || -n "${unexpected:-}" ]]; then
  printf 'Downloaded checksum has an invalid format or target.\n' >&2
  exit 1
fi
(
  cd "$download_directory"
  sha256sum --check --strict "$checksum_name"
)
if [[ "$draft" == true ]]; then
  cmp "$apk_path" "$download_directory/$apk_name"
fi
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}" \
  "$repository_root/tool/verify_android_release_artifact.sh" \
  "$download_directory/$apk_name"

if [[ "$draft" == true ]]; then
  gh release edit "$release_tag" \
    --repo "$canonical_repository" \
    --draft=false \
    --title "DevCoordinator $version_name"
fi

response="$(
  curl --fail --silent --show-error \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "https://api.github.com/repos/$canonical_repository/releases/latest"
)"
test "$(jq -r '.tag_name' <<<"$response")" = "$release_tag"
test "$(jq -r '.draft' <<<"$response")" = false
test "$(jq -r '.prerelease' <<<"$response")" = false
gh release view "$release_tag" \
  --repo "$canonical_repository" \
  --json url \
  --jq .url
