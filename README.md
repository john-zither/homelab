# homelab

Single-node k3s cluster for a workstation with one 6 GB GPU (RTX 2060) and
11 GB of RAM. It runs two projects that used to compete for the GPU under
cron, docker-compose and ad-hoc `docker start`:

- **media**: multi-voice audiobook generation ([storysearch](../storysearch))
  with AllTalk XTTS plus an LLM for speaker attribution, and a semantic
  search API.
- **trading**: the GNN paper-trading strategy, a REIT tracker, a dashboard,
  and a weekly GPU retrain ([stocks](../stocks)).

```
                        ┌──────────────────── k3s (Docker runtime) ─────────────────────┐
                        │                                                                │
 nvidia-device-plugin ──┤  GPU advertised as 12 slots (~0.5 GB VRAM each)                │
                        │                                                                │
 media                  │  alltalk (7 slots, 0↔1) ◄── audiobook Jobs ──► host Ollama     │
                        │  ollama-gpu-reservation (5 slots, 0↔1)       (127.0.0.1:11434) │
                        │  gpu-reaper CronJob: scales both to 0 when no Job is active    │
                        │  storysearch-api (CPU, 0↔1, NodePort 30802)                    │
                        │                                                                │
 trading                │  paper-linkgnn 09:35 America/New_York ─┐                       │
                        │  vgslx       15:10 America/New_York    ├─ Alpaca paper API      │
                        │  dashboard   16:30 America/New_York   ─┘                       │
                        │  paper-gnn, retrain-gnn (v1, suspended)                        │
                        │  dashboard-web (nginx, NodePort 30899)                         │
                        └────────────────────────────────────────────────────────────────┘
```

## Design decisions

**GPU slots as VRAM accounting.** The card has no memory isolation between
processes. The NVIDIA device plugin's time-slicing advertises it as 12
replicas, and each workload requests replicas in proportion to the VRAM it
really holds: AllTalk 7 (about 3.1 GB), Ollama 5 (about 2.3 GB), the stocks
retrain 4 (about 1.9 GB). The scheduler therefore never co-locates
workloads that don't fit. Under cron, the weekly retrain hit CUDA OOM next
to the TTS server and the failure went unnoticed. Here the retrain stays
Pending until the audiobook stack scales down, then runs.

**Scale to zero by default.** With 11 GB of RAM shared with a desktop, only
cheap things run continuously (device plugin, nginx). AllTalk, the Ollama
reservation and the search API start on demand. The `gpu-reaper` CronJob
scales the GPU stack back down when no audiobook Job is active. Without
it, a forgotten `up` would block the retrain indefinitely.

**Host Ollama plus a reservation pod.** Ollama stays a host service because
jobseeker and ragnas use it too. A second copy in the cluster would mean
another 3.4 GB image and two Ollamas fighting over one GPU. Instead, a
`pause` pod holds Ollama's 5 slots while the audiobook stack is up, so the
scheduler accounts for its VRAM. Blind spot: host Ollama use from other
apps outside that window isn't accounted for. Audiobook Jobs use
`hostNetwork` to reach Ollama on 127.0.0.1, so Ollama never has to listen
on the network.

**k3s on Docker (`--docker`).** k3s normally brings its own containerd and
image store. The AllTalk image alone is 14.7 GB, and the disk had about 20 GB
free before the runtime images (stocks 8 GB with CUDA torch, storysearch
2.2 GB) and is now at about 12 GB, so a second copy of every image is not an
option. With cri-dockerd,
pods use the images Docker already has, and the locally built runtime
images need no registry (`imagePullPolicy: Never`).
Sharing Docker's store has a cost: kubelet treats it as its own. Its image
GC deleted the runtime images (no container referenced them) minutes
after the first install, and its default 10%-free eviction threshold
tainted the node. `bootstrap/k3s-config.yaml` disables image GC and uses
absolute disk floors (3 GiB) instead.

**Runtime images, mounted code.** Each project's `Dockerfile` contains only
its Python environment, built from `uv.lock`. The project directory is
mounted at `/app`. Code changes take effect on the next run without a
rebuild, and jobs keep writing models, logs and data where the projects
expect them. Rebuild with `make images` when dependencies change. The
trade-off is that images aren't self-contained artifacts; on a one-node,
one-person cluster that's the right call. storysearch uses CPU-only torch
(2.2 GB image); stocks keeps CUDA torch for the GPU retrain.

**Cluster time zones instead of cron arithmetic.** CronJob `timeZone` pins
the trading jobs to New York time. Under Berlin-time cron, the 15:00
trade landed at 16:00 New York during the weeks when US and EU daylight
saving time disagree. `startingDeadlineSeconds` also states what happens
after the machine was off: trading jobs skip a missed slot (600 s), while
the retrain still runs up to 2 days late.

**No automatic retries for trading.** `backoffLimit: 0` on paper-linkgnn
and vgslx, because a retry after partially placed orders could double them.
Audiobook Jobs retry freely (`backoffLimit: 2`); generation resumes at the
chunk level.

## Setup

k3s needs apt `docker-ce`, not the docker snap. k3s starts pod containers
with `no-new-privileges`, and under the snap's AppArmor profile that
blocks the switch into `docker-default`, so every pod fails with
`exec /pause: operation not permitted`. `migrate-snap-docker.sh` moves the
snap's overlay2 data dir to `/var/lib/docker` (a rename on the same disk,
so no copy) and hands it to an upgraded docker-ce.

```bash
sudo ./bootstrap/migrate-snap-docker.sh   # only if Docker is still the snap
sudo ./bootstrap/install-k3s.sh   # NVIDIA as Docker's default runtime; k3s --docker; kubeconfig
make cluster                      # namespaces + device plugin
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'   # → 12
make images                       # homelab/{stocks,storysearch}-runtime
make secrets                      # Alpaca keys from ../stocks/keys.env
make deploy                       # everything; trading CronJobs start suspended
make validate                     # offline: render + kubeconform every kustomization
```

## Cutover from cron (trading)

The CronJobs ship `suspend: true` because the crontab runs the same scripts,
and both schedulers running means duplicate orders.

1. `crontab -e`: delete the four `agents/stocks/run_*.sh` lines.
2. `make trading-enable`. This refuses to run while those crontab lines exist.
3. Check after the next session: `kubectl -n trading get jobs`, `kubectl -n trading logs job/<name>`.

`make trading-disable` re-suspends them. The jobs append to the same
`stocks/logs/*.log` files as before, so the dashboard keeps working, and the
logs are also in `kubectl logs`.

## Day to day

```bash
make status                                        # pods, jobs, GPU slot usage
make audiobook ARGS='batch --count 10'             # Job + GPU stack up; reaper scales down after
scripts/audiobook.sh run generate "/media/theurerjohn3/My Passport/storysearch/inbox/book.epub" --unique-voices
make search-up                                     # http://localhost:30802/search?q=...
open http://localhost:30899                        # trading dashboard
kubectl -n media annotate deploy/alltalk homelab/keep-up=true   # keep AllTalk up for manual use
```

## Not (yet) in the cluster

ragnas and jobseeker (docker-compose) and host Ollama are unchanged. Migrating
the compose services is mechanical (Deployments plus hostPath volumes); host
Ollama would move in only if its other users did too.
