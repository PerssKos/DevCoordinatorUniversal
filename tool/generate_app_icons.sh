#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg with SVG input support is required." >&2
  exit 1
fi

icon_source="assets/branding/app_icon.svg"
round_icon_source="assets/branding/app_icon_round.svg"
android_root="apps/devcoordinator/android/app/src/main/res"
macos_root="apps/devcoordinator/macos/Runner/Assets.xcassets/AppIcon.appiconset"
windows_icon="apps/devcoordinator/windows/runner/resources/app_icon.ico"

render_png() {
  local size="$1"
  local destination="$2"
  local source="${3:-$icon_source}"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -y \
    -i "$source" \
    -vf "scale=${size}:${size}:flags=lanczos" \
    -frames:v 1 \
    "$destination"
}

android_sizes=(
  "mdpi:48"
  "hdpi:72"
  "xhdpi:96"
  "xxhdpi:144"
  "xxxhdpi:192"
)
for entry in "${android_sizes[@]}"; do
  density="${entry%%:*}"
  size="${entry##*:}"
  destination="$android_root/mipmap-$density/ic_launcher.png"
  render_png "$size" "$destination"
  render_png \
    "$size" \
    "$android_root/mipmap-$density/ic_launcher_round.png" \
    "$round_icon_source"
done

for size in 16 32 64 128 256 512 1024; do
  render_png "$size" "$macos_root/app_icon_${size}.png"
done

ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -i "$icon_source" \
  -vf "scale=256:256:flags=lanczos" \
  -frames:v 1 \
  "$windows_icon"

echo "Generated Android, macOS, and Windows icons from $icon_source and $round_icon_source."
