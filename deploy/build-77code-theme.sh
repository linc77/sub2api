#!/bin/bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p /opt/sub2api-builds
build_dir=${THEME_BUILD_DIR:-$(mktemp -d /opt/sub2api-builds/77code-theme.XXXXXX)}
mkdir -p "$build_dir/node_modules" "$build_dir/pnpm-store" "$build_dir/dist" "$build_dir/image"
source_commit=$(git -C "$repo_root" rev-parse HEAD)
short_commit=$(git -C "$repo_root" rev-parse --short=12 HEAD)
image="sub2api-77code:0.2.18-$short_commit"

docker run --rm --name "sub2api-theme-frontend-$short_commit" \
  --cpus=1 --memory=2048m --memory-swap=4096m --pids-limit=256 \
  --mount "type=bind,src=$repo_root/frontend,dst=/app/frontend" \
  --mount "type=bind,src=$build_dir/node_modules,dst=/app/frontend/node_modules" \
  --mount "type=bind,src=$build_dir/pnpm-store,dst=/app/frontend/.pnpm-store" \
  --mount "type=bind,src=$build_dir/dist,dst=/app/backend/internal/web/dist" \
  --mount "type=bind,src=$repo_root/docs/legal,dst=/app/docs/legal,readonly" \
  --mount "type=bind,src=$repo_root/deploy/build-themed-frontend.mjs,dst=/app/deploy/build-themed-frontend.mjs,readonly" \
  --workdir /app/frontend \
  --env CI=true --env NODE_OPTIONS=--max-old-space-size=1536 \
  node:24-alpine sh -c \
  'corepack enable && corepack prepare pnpm@9.15.9 --activate && pnpm install --frozen-lockfile --store-dir /app/frontend/.pnpm-store --network-concurrency 4 --child-concurrency 1 && node /app/deploy/build-themed-frontend.mjs'

mkdir -p "$repo_root/backend/internal/web/dist"
cp -a "$build_dir/dist/." "$repo_root/backend/internal/web/dist/"
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
(
  cd "$repo_root/backend"
  GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" GOSUMDB="${GOSUMDB:-sum.golang.google.cn}" \
    GOTOOLCHAIN=local GOMAXPROCS=1 GOMEMLIMIT=512MiB GOGC=50 CGO_ENABLED=0 \
    nice -n 10 go build -p 1 -tags embed -trimpath \
    -ldflags="-s -w -X main.Version=0.2.18 -X main.Commit=$source_commit -X main.Date=$build_date -X main.BuildType=source" \
    -o "$build_dir/image/sub2api" ./cmd/server
)

# The build context contains only the binary and Dockerfile, never production data.
cp "$repo_root/deploy/Dockerfile.77code-theme" "$build_dir/image/Dockerfile"
DOCKER_BUILDKIT=0 docker build --build-arg "SOURCE_COMMIT=$source_commit" \
  --tag "$image" "$build_dir/image"
printf '%s\n' "$image" > "$build_dir/image-tag.txt"
printf 'Built %s\n' "$image"
