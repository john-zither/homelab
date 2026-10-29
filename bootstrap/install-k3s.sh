#!/usr/bin/env bash
# One-time cluster bootstrap. Review, then run:  sudo ./bootstrap/install-k3s.sh
#
# 1. Docker on this machine is the snap (data in /var/snap/docker). An apt
#    docker.service is also installed but fails at every boot (bridge conflict
#    with the snap daemon). Restarting it lets its docker.socket take over
#    /var/run/docker.sock, which cuts the docker CLI off from the snap daemon.
#    So the apt units are disabled for good.
# 2. Makes the NVIDIA runtime the snap Docker's default, so GPU containers
#    (and the NVIDIA device plugin) can see the card, and lets the snap mount
#    /media (the storysearch drive). Restarts Docker; containers with a
#    restart policy (ragnas, jobseeker, postgres, ...) come back up.
# 3. Installs single-node k3s on Docker (--docker) instead of k3s's own
#    containerd, so the cluster reuses Docker's image store: the AllTalk image
#    alone is 14.7 GB and the disk has ~12 GB free, so a second copy won't fit.
#    Traefik and the service load balancer are disabled; NodePorts suffice.
# 4. Copies the kubeconfig to the invoking user's ~/.kube/config.
set -euo pipefail

if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" ]]; then
    echo "Run with sudo from your normal user: sudo $0" >&2
    exit 1
fi
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
SNAP_DOCKER_CONFIG=/var/snap/docker/current/config/daemon.json

if ! snap list docker >/dev/null 2>&1; then
    echo "Expected the docker snap; this script is written for it." >&2
    exit 1
fi

echo "== 1/4 Disabling the unused apt docker.service/docker.socket"
systemctl disable --now docker.socket docker.service 2>/dev/null || true

echo "== 2/4 Snap Docker: NVIDIA runtime as default, /media access"
python3 - "$SNAP_DOCKER_CONFIG" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
if "nvidia" not in cfg.get("runtimes", {}):
    sys.exit(f"{path} has no 'nvidia' runtime; check the snap's NVIDIA support")
cfg["default-runtime"] = "nvidia"
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
EOF
snap connect docker:removable-media
snap restart docker
for _ in $(seq 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker info --format 'Docker {{.ServerVersion}}, default runtime: {{.DefaultRuntime}}'

echo "== 3/4 Installing k3s (stable channel, Docker runtime)"
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable \
    INSTALL_K3S_EXEC="server --docker --disable traefik --disable servicelb --write-kubeconfig-mode 600" sh -

echo "== 4/4 kubeconfig for $SUDO_USER"
install -d -m 700 -o "$SUDO_USER" -g "$SUDO_USER" "$USER_HOME/.kube"
install -m 600 -o "$SUDO_USER" -g "$SUDO_USER" /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"

echo "Done. As $SUDO_USER, continue with:  make cluster"
