#!/bin/sh
set -eu

OPS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$OPS_DIR/common-77code.sh"

printf '== Docker containers ==\n'
if "$DOCKER" info >/dev/null 2>&1; then
  "$DOCKER" ps -a \
    --filter "name=^/${APP_CONTAINER}$" \
    --filter "name=^/${POSTGRES_CONTAINER}$" \
    --filter "name=^/${REDIS_CONTAINER}$" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
fi

printf '\n== Health checks ==\n'
exec sh "$OPS_DIR/healthcheck-77code.sh"
