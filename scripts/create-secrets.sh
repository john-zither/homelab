#!/usr/bin/env bash
# Create/refresh the Alpaca paper-trading secret from stocks/keys.env
# (lines like 'export ALPACA_API_KEY=...'). Values never touch this repo.
set -euo pipefail
AGENTS="$(cd "$(dirname "$0")/../.." && pwd)"
env_file=$(mktemp)
trap 'rm -f "$env_file"' EXIT
sed -E 's/^export +//' "$AGENTS/stocks/keys.env" | grep -E '^[A-Z_]+=' > "$env_file"
kubectl -n trading create secret generic alpaca --from-env-file="$env_file" \
    --dry-run=client -o yaml | kubectl apply -f -
