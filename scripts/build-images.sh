#!/usr/bin/env bash
# Build the runtime images into Docker, which k3s (--docker) uses directly.
# Tagged :latest (what the manifests use) and with a short hash of the project's
# uv.lock, so 'docker images' shows which dependency set each image holds.
set -euo pipefail
AGENTS="$(cd "$(dirname "$0")/../.." && pwd)"
for project in stocks storysearch; do
    lock=$(sha256sum "$AGENTS/$project/uv.lock" | cut -c1-12)
    echo "== homelab/$project-runtime (uv.lock $lock)"
    docker build -t "homelab/$project-runtime:latest" -t "homelab/$project-runtime:$lock" "$AGENTS/$project"
done
