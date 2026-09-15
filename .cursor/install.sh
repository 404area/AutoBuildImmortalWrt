#!/usr/bin/env bash
# Idempotent dependency setup for the AutoBuildImmortalWrt Cloud Agent environment.
#
# The firmware build runs the official immortalwrt/imagebuilder Docker image
# (see the .github/workflows/*.yml and per-platform build*.sh scripts), so the
# only real dependency is a working Docker Engine that can run nested inside the
# Cloud Agent VM. The daemon itself is launched per boot by .cursor/start.sh.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# fuse-overlayfs lets Docker use an overlay storage driver without a host
# overlay kernel module, which is required for Docker-in-Docker in the VM.
# --force-confold keeps any pre-existing /etc/fuse.conf so the install stays
# non-interactive.
sudo apt-get update -qq
sudo apt-get install -y -o Dpkg::Options::=--force-confold \
  docker.io \
  fuse3 \
  fuse-overlayfs \
  iptables \
  uidmap

# Allow the "ubuntu" agent user to talk to the Docker socket without sudo.
# start.sh launches dockerd with `--group ubuntu` so the socket is group-owned
# by a group this user already belongs to.
sudo groupadd -f docker

# The per-platform build scripts are invoked as `bash build.sh` inside the
# imagebuilder container (see the workflows), so no chmod is required here.

echo "install.sh completed: $(docker --version)"
