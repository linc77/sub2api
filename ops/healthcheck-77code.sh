#!/bin/sh
set -eu

OPS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$OPS_DIR/common-77code.sh"

# Monitoring is read-only: report failures without restarting live services.
failed=0
if "$DOCKER" info >/dev/null 2>&1; then
  for container in "$POSTGRES_CONTAINER" "$REDIS_CONTAINER" "$APP_CONTAINER"; do
    if state=$(container_state "$container" 2>/dev/null); then
      printf '%s: %s\n' "$container" "$state"
      case "$state" in
        healthy|running) ;;
        *) failed=1 ;;
      esac
    else
      printf '%s: missing or inaccessible\n' "$container" >&2
      failed=1
    fi
  done
else
  printf 'Docker is unavailable\n' >&2
  failed=1
fi

check_endpoint 'Local health' "$LOCAL_HEALTH_URL" || failed=1
check_endpoint 'Public health' "$PUBLIC_HEALTH_URL" || failed=1
exit "$failed"
