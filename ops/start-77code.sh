#!/bin/sh
set -eu

OPS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$OPS_DIR/common-77code.sh"

# Start the existing deployment without recreating containers or resolving
# Compose paths. The application and databases may belong to different projects.
if ! "$DOCKER" info >/dev/null 2>&1; then
  printf 'Docker is unavailable; start the Docker engine first\n' >&2
  exit 1
fi

# Validate every container before starting any of them.
for container in "$POSTGRES_CONTAINER" "$REDIS_CONTAINER" "$APP_CONTAINER"; do
  if ! state=$(container_state "$container" 2>/dev/null); then
    printf 'Container %s is missing; see deploy/VPS_REBUILD_CN.md for initial deployment\n' "$container" >&2
    exit 1
  fi
  case "$state" in
    healthy|running|starting|restarting|exited|created) ;;
    *) printf '%s is %s; manual inspection required\n' "$container" "$state" >&2; exit 1 ;;
  esac
done

for container in "$POSTGRES_CONTAINER" "$REDIS_CONTAINER" "$APP_CONTAINER"; do
  state=$(container_state "$container")
  case "$state" in
    exited|created) "$DOCKER" start "$container" ;;
    *) printf '%s: already running\n' "$container" ;;
  esac
  wait_for_container "$container"
done

check_endpoint 'Local health' "$LOCAL_HEALTH_URL"
