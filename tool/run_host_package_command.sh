#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: NEEDRESTART_MODE=l $0 <package-manager command...>" >&2
  exit 64
fi

if [[ "${NEEDRESTART_MODE:-}" != "l" ]]; then
  echo "refusing host package transaction: NEEDRESTART_MODE must be l (list only)" >&2
  exit 65
fi

exec "$@"
