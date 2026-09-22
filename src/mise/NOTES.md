The official release binary from [GitHub Releases](https://github.com/jdx/mise/releases)
is installed as `/usr/local/bin/mise`, and the directories mise installs tools into
and caches downloads in are placed on volumes the feature declares.

## Requirements

- A `linux-x64` or `linux-arm64` image. The statically linked musl build is the one
  installed, so it runs whatever the image's libc is. The libc that tools mise
  installs are built for is detected from the image, not from that build.
- `wget` (or `curl`), `sha256sum` and a CA bundle, for the download and the checksum
  check. Any of those the image is missing are installed with `apt-get`, so an image
  without them has to be Debian or Ubuntu based.

## Usage

The feature takes no options:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1": {}
}
```

The checksums committed with the feature cover one mise release, so the feature
version is what selects which mise is installed. A tag such as `:1` resolves to the
newest feature release when the container is built; pin it to hold a mise release:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1.0.0": {}
}
```

## Installed software

- mise, the statically linked `linux-*-musl` build, installed as
  `/usr/local/bin/mise` and owned by root.

Nothing else: no tool is installed until the project asks for it. The shims
directory is on `PATH`, so a tool resolves as soon as mise installs it, including
for programs that do not load the shell configuration.

## Tool installs and download cache

mise keeps its tool installs in `MISE_DATA_DIR` and its download cache in
`MISE_CACHE_DIR`. The feature declares a volume for each and points mise at them:

```json
"containerEnv": {
    "MISE_DATA_DIR": "/var/lib/mise",
    "MISE_CACHE_DIR": "/var/cache/mise",
    "PATH": "/var/lib/mise/shims:${PATH}"
},
"mounts": [
    {
        "source": "${devcontainerId}-mise-data",
        "target": "/var/lib/mise",
        "type": "volume"
    },
    {
        "source": "${devcontainerId}-mise-cache",
        "target": "/var/cache/mise",
        "type": "volume"
    }
]
```

Both directories belong to a `mise` system group the remote user is added to, and
are group-writable and setgid, so they stay writable after the Dev Containers CLI
renumbers the remote user's UID.

If an existing volume is reused after the host user's UID changed, files written
under the old UID keep their owner-only modes and mise cannot replace them; clear
them with `rm -rf /var/lib/mise/* /var/cache/mise/*` (this removes the installed
tools) or remove the volumes.

The volumes are per dev container (`${devcontainerId}`). To share one across
projects, or to put a directory somewhere else, declare a mount on the same target
in `devcontainer.json`: mounts are merged by target with the last one winning, and
`devcontainer.json` is merged last, so it replaces the feature's.

```json
"mounts": [
    {
        "source": "mise-data-shared",
        "target": "/var/lib/mise",
        "type": "volume"
    }
]
```

`containerEnv` is merged the same way, so setting `MISE_DATA_DIR` or
`MISE_CACHE_DIR` there points mise elsewhere and leaves the feature's mount in place
and unused; `PATH` then needs the new shims directory as well.

mise's configuration (`~/.config/mise`) and state, including which `mise.toml` files
have been trusted (`~/.local/state/mise`), stay in the remote user's home directory
and are recreated by a rebuild.

## Not installed

- **No language runtime or tool.** mise resolves the versions the project declares.
- **No development headers beyond libc.** A backend that downloads prebuilt binaries
  works as-is; one that builds from source needs the `-dev` packages of the
  libraries it links against.
- **No shell activation.** The shell configuration is left untouched; the shims
  directory on `PATH` is what makes installed tools resolve.

## Supply chain

The binary is downloaded from `https://github.com/jdx/mise/releases/` and checked
against `SHASUMS256.txt`, vendored with the feature: upstream's own checksum file,
committed verbatim together with the minisign signature upstream published for it.
Checking the download therefore needs `sha256sum` and nothing else.

The signature is verified in CI rather than in the container. The `CI` workflow runs
[`scripts/verify-material.sh`](https://github.com/bare-devcontainer/features/blob/main/scripts/verify-material.sh)
on every change, which checks `SHASUMS256.txt` against `SHASUMS256.txt.minisig`
using the vendored public key.

The public key is a copy of
[`minisign.pub`](https://github.com/jdx/mise/blob/main/minisign.pub) from the mise
repository, refreshed by this repository's `Update Trusted Material` workflow. The
checksums move only when the pinned release does, through
[`scripts/pin-checksums.sh`](https://github.com/bare-devcontainer/features/blob/main/scripts/pin-checksums.sh),
which writes what it downloaded only once the signature verifies.

To check the material yourself before pinning the feature:

```sh
minisign -V -m src/mise/SHASUMS256.txt \
    -x src/mise/SHASUMS256.txt.minisig \
    -p src/mise/mise-minisign.pub
```

`grep linux-x64 src/mise/SHASUMS256.txt` shows the release they pin.

This covers the mise binary only. Tools that mise installs at runtime are fetched
from their own upstreams under mise's own verification.

Everything downloaded during installation goes to a temporary directory that is
removed when the script exits.

## Tips

- For the tags this feature is published under, see
  [Versions and pinning](https://github.com/bare-devcontainer/features#versions-and-pinning).
- [`MISE_PARANOID`](https://mise.jdx.dev/paranoid.html) in `containerEnv` makes mise
  re-verify the provenance of the tools it installs and refuse untrusted
  configuration.
- A rebuild clears which `mise.toml` files mise has trusted. Set
  `MISE_TRUSTED_CONFIG_PATHS` to the workspace folder in `containerEnv` to trust the
  project's up front.
