#!/usr/bin/env bash
# Start the Docker daemon for the AutoBuildImmortalWrt Cloud Agent environment.
#
# The Cloud Agent VM does not run systemd (PID 1 is tini), so the daemon is
# launched directly here on every boot. This script is idempotent: if a healthy
# daemon is already running it returns immediately.
set -euo pipefail

if docker info >/dev/null 2>&1; then
  echo "dockerd already running"
  exit 0
fi

# Remove a stale pid file left behind by a previous boot/snapshot.
sudo rm -f /var/run/docker.pid

# fuse-overlayfs: overlay storage without a host overlay module.
# --group ubuntu: make /var/run/docker.sock usable by the agent user (no sudo).
sudo nohup dockerd \
  --storage-driver=fuse-overlayfs \
  --group ubuntu \
  >/tmp/dockerd.log 2>&1 &

for _ in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    echo "dockerd ready"
    docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}' || true
    exit 0
  fi
  sleep 2
done

echo "ERROR: dockerd did not become ready in time" >&2
tail -n 50 /tmp/dockerd.log >&2 || true
exit 1
