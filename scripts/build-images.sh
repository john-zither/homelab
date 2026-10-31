#!/usr/bin/env bash
# Build the runtime images into Docker, which k3s (--docker) uses directly.
# Tagged :latest (what the manifests use) and with a short hash of the project's
# uv.lock, so 'docker images' shows which dependency set each image holds.
set -euo pipefail
AGENTS="$(cd "$(dirname "$0")/../.." && pwd)"
# image name:project directory
for spec in stocks:stocks storysearch:storysearch smard:smard/demand; do
    name=${spec%%:*} dir="$AGENTS/${spec#*:}"
    lock=$(sha256sum "$dir/uv.lock" | cut -c1-12)
    echo "== homelab/$name-runtime (uv.lock $lock)"
    docker build -t "homelab/$name-runtime:latest" -t "homelab/$name-runtime:$lock" "$dir"
done
