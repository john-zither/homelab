#!/usr/bin/env bash
# One-time cluster bootstrap. Review, then run:  sudo ./bootstrap/install-k3s.sh
#
# 1. Makes the NVIDIA runtime Docker's default, so GPU containers (and the
#    NVIDIA device plugin) can see the card. This restarts Docker; containers
#    with a restart policy (ragnas, jobseeker, postgres, ...) come back up.
# 2. Installs single-node k3s on Docker (--docker) instead of k3s's own
#    containerd, so the cluster reuses Docker's image store: the AllTalk image
#    alone is 14.7 GB and the disk has ~20 GB free, so a second copy won't fit.
#    Traefik and the service load balancer are disabled; NodePorts suffice.
# 3. Copies the kubeconfig to the invoking user's ~/.kube/config.
set -euo pipefail

if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" ]]; then
    echo "Run with sudo from your normal user: sudo $0" >&2
    exit 1
fi
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

echo "== 1/3 NVIDIA runtime as Docker default"
nvidia-ctk runtime configure --runtime=docker --set-as-default
systemctl restart docker

echo "== 2/3 Installing k3s (stable channel, Docker runtime)"
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable \
    INSTALL_K3S_EXEC="server --docker --disable traefik --disable servicelb --write-kubeconfig-mode 600" sh -

echo "== 3/3 kubeconfig for $SUDO_USER"
install -d -m 700 -o "$SUDO_USER" -g "$SUDO_USER" "$USER_HOME/.kube"
install -m 600 -o "$SUDO_USER" -g "$SUDO_USER" /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"

echo "Done. As $SUDO_USER, continue with:  make cluster"
