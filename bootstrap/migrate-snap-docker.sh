#!/usr/bin/env bash
# One-time move from the docker snap to apt docker-ce. Review, then run:
#   sudo ./bootstrap/migrate-snap-docker.sh
#
# Why: k3s starts pod containers with no-new-privileges. Under the snap's
# AppArmor confinement (snap.docker.dockerd), no-new-privileges forbids the
# switch into the docker-default profile, so every pod fails with
# "exec /pause: operation not permitted". Plain `docker run` doesn't set
# no-new-privileges, which is why the snap worked for everything else.
#
# How: the snap keeps its state as plain overlay2 under
# /var/snap/docker/common/var-lib-docker, on the same filesystem as
# /var/lib/docker. A rename moves every image, container and volume without
# copying. docker-ce is upgraded first so it is not older than the snap
# (29.8) that wrote the data. The old, never-working apt data dir is set
# aside, not deleted.
#
# Rollback:  systemctl stop docker.socket docker.service
#            mv /var/lib/docker /var/snap/docker/common/var-lib-docker
#            snap start --enable docker
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0" >&2
    exit 1
fi
SNAP_ROOT=/var/snap/docker/common/var-lib-docker
if [[ ! -d $SNAP_ROOT ]]; then
    echo "$SNAP_ROOT not found; already migrated?" >&2
    exit 1
fi

echo "== 1/5 Stopping k3s and the docker snap"
systemctl stop k3s 2>/dev/null || true
snap stop --disable docker

echo "== 2/5 Upgrading docker-ce"
apt-get update -q
apt-get install -y --only-upgrade docker-ce docker-ce-cli containerd.io
# The package scripts may have started the apt daemon on its old data dir.
systemctl stop docker.socket docker.service

echo "== 3/5 Moving the snap's data to /var/lib/docker"
if [[ -e /var/lib/docker ]]; then
    mv /var/lib/docker "/var/lib/docker.apt-unused-$(date +%Y%m%d)"
fi
mv "$SNAP_ROOT" /var/lib/docker

echo "== 4/5 NVIDIA as default runtime; starting docker-ce"
nvidia-ctk runtime configure --runtime=docker --set-as-default
systemctl enable --now docker.socket docker.service
docker info --format 'Docker {{.ServerVersion}}, root {{.DockerRootDir}}, default runtime {{.DefaultRuntime}}'

echo "== 5/5 Starting k3s"
systemctl start k3s 2>/dev/null || echo "(k3s not installed yet; run install-k3s.sh)"

echo
echo "Done. The old apt data dir (never used successfully) can be checked and removed:"
echo "  du -sh /var/lib/docker.apt-unused-*   then   rm -rf /var/lib/docker.apt-unused-*"
echo "Once everything works: snap remove docker"
