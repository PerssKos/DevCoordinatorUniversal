#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 tool/validate_native_gateway.py \
  --self-test \
  contracts/native-gateway.openapi.yaml
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/coordinator_client
flutter test packages/devcoordinator_design
flutter test packages/release_update
flutter test apps/devcoordinator
