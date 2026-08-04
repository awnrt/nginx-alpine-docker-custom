# nginx-alpine-docker-custom

This project provides a patched build workflow based on [nginx-custom-build](https://git.bloat.cat/vlnst/nginx-custom-build).

It uses the original repository as a dependency and applies a local patch to modify the build process. To build the image, simply run:

```sh
./docker-build.sh
````

The script will fetch the submodule, apply the patch, and build the Docker image.

## Server deployment (optional)

To automatically push the built image to your server, copy:

```sh
cp environment.example environment
```

Then edit `environment` and set your server username and domain:

```sh
REMOTEUSER=your_username
REMOTEDOMAIN=your_domain
```

If these variables are configured, the build script will automatically transfer the Docker image to your server after building.

## Changes from upstream

The original `nginx-custom-build` project produces a x86_64-v3 `.deb` package.

This patch changes the build process to:

* Build a minimal Alpine-based nginx image
* Target x86_64-v4 CPU features
* Keep the auto-index module enabled
