#!/bin/sh
set -eu

IMAGE="${IMAGE:-nginx-custom}"
VERSION="${VERSION:-dev}"

# copy environment.example to environment and change vars
# if you want to auto push it to your server
if [ -f ./environment ]; then
    . ./environment
fi

docker build \
    -t "${IMAGE}:${VERSION}" \
    -t "${IMAGE}:latest" \
    --no-cache \
    .

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "Running in GitHub Actions, skipping image export"
elif [ -n "${REMOTEUSER:-}" ] && [ -n "${REMOTEDOMAIN:-}" ]; then
    docker save "${IMAGE}:latest" | zstd -T0 -19 | ssh "${REMOTEUSER}@${REMOTEDOMAIN}" "zstd -d | docker load"
else
    docker save "${IMAGE}:latest" | zstd -T0 -19 -o nginx-custom.tar.zst
fi
