#!/usr/bin/env bash
# Start a demand-model training Job on the GPU and follow its log.
set -euo pipefail
cd "$(dirname "$0")/.."
job=$(kubectl create -f apps/energy/demand-train-job.yaml -o name)
echo "$job"
kubectl -n energy wait --for=condition=ready pod -l "job-name=${job#job.batch/}" --timeout=1h
kubectl -n energy logs -f "$job"
