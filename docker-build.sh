#!/bin/sh
set -eu

git submodule sync --recursive
git submodule update --init --recursive --remote
cd nginx-custom-build
# Make sure we start from a clean upstream state
git reset --hard
git clean -fd
patch -p1 < ../patches/build.sh.patch
cp build.sh ..
cd ..

# copy environment.example to environment and change vars
# if you want to auto push it to your server
. ./environment

docker build --no-cache -t nginx-custom .

if [ -n "${REMOTEUSER:-}" ] && [ -n "${REMOTEDOMAIN:-}" ]; then
    docker save nginx-custom:latest | zstd -T0 -19 | ssh "${REMOTEUSER}@${REMOTEDOMAIN}" "zstd -d | docker load"
else
    docker save nginx-custom:latest | zstd -T0 -19 -o nginx-custom.tar.zst
fi
