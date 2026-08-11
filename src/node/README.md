
# Node.js (node)

Installs Node.js from nodejs.org, verified against the Node.js release signing keys, with Corepack in place of npm.

## Example Usage

```json
"features": {
    "ghcr.io/bare-devcontainer/features/node:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Node.js version to install. Use "lts" for the newest long-term support release, "latest" for the newest release of any line, a release line such as "24" or "24.19", or an exact version such as "24.19.0". | string | lts |
| corepack | npm version specifier of Corepack to install globally, or "none" to leave Corepack out. | string | latest |
| keepNpm | Keep the npm and npx executables that ship with the Node.js distribution. When false, both are removed so the package manager comes from the project's "packageManager" field through Corepack. | boolean | false |

## Details

This feature installs the same Node.js setup as the
[`ghcr.io/bare-devcontainer/node`](https://github.com/bare-devcontainer/images/tree/main/node)
image, for base images that do not already carry it: the official build from
[nodejs.org](https://nodejs.org/dist/) unpacked into `/usr/local`, Corepack from
npm, and no npm left behind.

- Requires a glibc based `linux-x64` or `linux-arm64` image.
- The download, signature check and unpacking need `wget` (or `curl`), `gpgv`,
  `tar`, `xz` and `sha256sum`. Any of those the image is missing are installed
  with `apt-get`, so an image without them has to be Debian or Ubuntu based.

### Version selection

`version` accepts `lts` (the newest long-term support release), `latest` (the
newest release of any line), a release line such as `24` or `24.19`, or an exact
version such as `24.19.0`. Everything but an exact version is resolved against
`https://nodejs.org/dist/index.json` at install time, so a rebuild picks up
newer patch releases.

### Corepack instead of npm

npm and npx are removed after Corepack is installed, so the package manager
comes from the project's `packageManager` field rather than from the image:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/node:1": {}
}
```

Corepack is installed but not enabled, matching the image. Its shims go into
`/usr/local/bin`, so enabling them needs root — a `RUN corepack enable` in a
`Dockerfile` layered on the image, for instance. Without root, `corepack enable
--install-directory` writes them somewhere the remote user owns instead.

Set `keepNpm` to `true` to keep npm and npx, or `corepack` to `none` to leave
Corepack out. Corepack is installed with npm, so `corepack: "none"` together
with `keepNpm: false` yields a Node.js with no package manager at all.

Corepack downloads package managers into `COREPACK_HOME`, which defaults to
`~/.cache/node/corepack`. The feature creates that directory for the remote user
so the first `corepack` call does not have to write into a root-owned cache.

### Supply chain

The release tarball is downloaded from `https://nodejs.org/dist/` and its
checksum is verified against `SHASUMS256.txt.asc`, signed by the Node.js Release
Team. The keyring is vendored with the feature and read from there, so
signatures are checked against keys reviewed in this repository rather than keys
fetched at install time. It is a copy of the keyring published by
[nodejs/release-keys](https://github.com/nodejs/release-keys), refreshed by this
repository's `Update Trusted Material` workflow.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bare-devcontainer/features/blob/main/src/node/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
