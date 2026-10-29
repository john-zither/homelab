#!/usr/bin/env bash
# Audiobook generation on the cluster.
#
#   scripts/audiobook.sh run batch --count 10      # any storysearch main.py args
#   scripts/audiobook.sh run generate /media/theurerjohn3/My\ Passport/storysearch/inbox/book.epub --unique-voices
#   scripts/audiobook.sh up | down | status
#
# 'run' creates the Job; its driver scales the GPU stack per phase (speaker
# attribution with the Ollama reservation, then synthesis with AllTalk). The
# gpu-reaper CronJob scales everything to zero once no audiobook Job is active.
# 'up' starts AllTalk alone, for manual use.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NS=media

up()   { kubectl -n $NS scale deploy/alltalk --replicas=1; }
down() { kubectl -n $NS scale deploy/alltalk deploy/ollama-gpu-reservation --replicas=0; }

case "${1:-}" in
    run)
        shift
        [[ $# -gt 0 ]] || { echo "usage: $0 run <main.py args...>" >&2; exit 1; }
        name="audiobook-$(date +%Y%m%d-%H%M%S)"
        args=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@")
        python3 - "$HERE/apps/media/audiobook-job.yaml.tmpl" "$name" "$args" <<'PY' | kubectl create -f -
import sys
tmpl, name, args = sys.argv[1:]
print(open(tmpl).read().replace("__NAME__", name).replace("__ARGS__", args))
PY
        echo "Follow with:  kubectl -n $NS logs -f job/$name"
        ;;
    up) up ;;
    down) down ;;
    status)
        kubectl -n $NS get deploy alltalk ollama-gpu-reservation
        kubectl -n $NS get jobs -l app=audiobook
        ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
