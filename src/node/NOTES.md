The official build from [nodejs.org](https://nodejs.org/dist/) is unpacked into
`/usr/local`, Corepack is installed from npm, and npm itself is removed afterwards.

## Requirements

- A glibc based `linux-x64` or `linux-arm64` image, since that is the official
  build being installed.
- `wget` (or `curl`), `gpgv`, `tar`, `xz`, `sha256sum` and a CA bundle, for the
  download, signature check and unpacking. Any of those the image is missing are
  installed with `apt-get`, so an image without them has to be Debian or Ubuntu
  based; an image that already has them needs no package manager at all.

## Usage

The defaults install the newest long-term support release with the newest Corepack,
and remove npm. To pin a release line and keep npm:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/node:1": {
        "version": "24",
        "keepNpm": true
    }
}
```

## Version selection

`version` accepts `lts` (the newest long-term support release), `latest` (the
newest release of any line), a release line such as `24` or `24.19`, or an exact
version such as `24.19.0`. Everything but an exact version is resolved against
`https://nodejs.org/dist/index.json` at install time, so a rebuild picks up
newer patch releases.

## Installed software

- Node.js, unpacked into `/usr/local`, owned by root.
- Corepack, installed globally from npm at the version `corepack` specifies.

Corepack downloads package managers into `COREPACK_HOME`, which defaults to
`~/.cache/node/corepack`. The feature creates that directory for the remote user
so the first `corepack` call does not have to write into a root-owned cache.

## Not installed

- **No npm or npx.** Both are removed after Corepack is installed, so the package
  manager comes from the project's `packageManager` field rather than from the
  image. Set `keepNpm` to `true` to keep them.
- **No enabled package manager.** Corepack is installed but not enabled. Its shims go
  into `/usr/local/bin`, so enabling them needs root — a `RUN corepack enable` in a
  `Dockerfile` layered on the image, for instance. Without root,
  `corepack enable --install-directory` writes them somewhere the remote user owns
  instead.
- **No package manager at all**, if you ask for that: `corepack: "none"` leaves
  Corepack out — including the copy that release lines up to Node.js 24 bundle,
  which is removed along with it — and combined with `keepNpm: false` yields a
  Node.js with nothing to install packages with.
- **No global JavaScript tooling.** Linters, formatters and test runners are left to
  the project's own dependencies.

## Supply chain

The release tarball is downloaded from `https://nodejs.org/dist/` and its
checksum is verified against `SHASUMS256.txt.asc`, signed by the Node.js Release
Team. The keyring is vendored with the feature and read from there, so
signatures are checked against keys reviewed in this repository rather than keys
fetched at install time. It is a copy of the keyring published by
[nodejs/release-keys](https://github.com/nodejs/release-keys), refreshed by this
repository's `Update Trusted Material` workflow.

To see the keys before pinning the feature:

```sh
gpg --no-default-keyring --keyring "$PWD/src/node/node-keyring.kbx" --list-keys
```

Everything downloaded during installation — the tarball, the checksums and npm's
cache — goes to a temporary directory that is removed when the script exits.

## Tips

- For the tags this feature is published under, see
  [Versions and pinning](https://github.com/bare-devcontainer/features#versions-and-pinning).
- If you enable npm through Corepack, keep its download cache across rebuilds by
  adding a named volume to `mounts` in `devcontainer.json`, with the target set to
  `.npm` in the remote user's home directory:

  ```json
  {
      "source": "${devcontainerId}-npm-cache",
      "target": "/home/dev/.npm",
      "type": "volume"
  }
  ```
