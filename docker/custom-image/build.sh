#!/usr/bin/env bash
# Build this lab's custom DSDL "golden" container image.
#
# Thin extension of the published golden image (see ./Dockerfile) with the extra
# Python libs from ./requirements.extra.txt layered on top. Builds a LOCAL tag —
# Splunk runs on the same machine, so there's nothing to push to a registry.
#
# Usage:
#   ./build.sh                                            # default base + tag
#   BASE=splunk/mltk-container-golden-gpu:5.2.3 ./build.sh   # different base / GPU
#   TAG=myrepo/mltk-container-custom:1.0 ./build.sh          # custom tag
#
# After building, point the lab at it (already the default in setup.sh):
#   GOLDEN_IMAGE=splunkaitk/mltk-container-custom:local in docker/.env
#   docker compose -f docker/docker-compose.yml up -d --force-recreate mltk-dev

set -euo pipefail

# Git Bash on Windows mangles Unix paths passed to docker.exe; disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE="${BASE:-splunk/mltk-container-golden-cpu:5.2.3}"
TAG="${TAG:-splunkaitk/mltk-container-custom:local}"

echo "==> Checking Docker is running"
docker info >/dev/null 2>&1 || { echo "ERROR: Docker isn't reachable. Start Docker Desktop and retry."; exit 1; }

echo "==> Building $TAG"
echo "    base: $BASE  (pulled automatically as the FROM)"
docker build --build-arg BASE="$BASE" -t "$TAG" .

echo
echo "Done. Built $TAG  (extra libs from requirements.extra.txt)"
echo "Next: ./setup.sh (uses this tag by default), or recreate just the dev container:"
echo "  docker compose -f docker/docker-compose.yml up -d --force-recreate mltk-dev"
