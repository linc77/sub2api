#!/bin/sh

# Shared settings; callers locate this file relative to their own script.
DOCKER=${DOCKER:-docker}
CURL=${CURL:-curl}
APP_CONTAINER=${APP_CONTAINER:-sub2api}
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-sub2api-postgres}
REDIS_CONTAINER=${REDIS_CONTAINER:-sub2api-redis}
LOCAL_HEALTH_URL=${LOCAL_HEALTH_URL:-http://127.0.0.1:8081/health}
PUBLIC_HEALTH_URL=${PUBLIC_HEALTH_URL:-https://77code.cc/health}
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-10}
START_WAIT_SECONDS=${START_WAIT_SECONDS:-60}

container_state() {
  "$DOCKER" inspect --format \
    '{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}{{.State.Status}}{{end}}' \
    "$1"
}

check_endpoint() {
  if "$CURL" --fail --silent --show-error --max-time "$HEALTH_TIMEOUT" "$2" >/dev/null; then
    printf '%s: ok\n' "$1"
  else
    printf '%s: failed (%s)\n' "$1" "$2" >&2
    return 1
  fi
}

wait_for_container() {
  waited=0
  while :; do
    state=$(container_state "$1") || return 1
    case "$state" in
      healthy|running) return 0 ;;
      starting|restarting) ;;
      *) printf '%s is %s; manual inspection required\n' "$1" "$state" >&2; return 1 ;;
    esac
    if [ "$waited" -ge "$START_WAIT_SECONDS" ]; then
      printf 'Timed out waiting for %s\n' "$1" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}
