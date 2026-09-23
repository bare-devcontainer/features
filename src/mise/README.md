
# mise (mise)

Installs mise, the polyglot tool and runtime manager, from its GitHub release, verified against checksums committed to this repository.

## Example Usage

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:2026": {}
}
```



The official release binary from [GitHub Releases](https://github.com/jdx/mise/releases)
is installed as `/usr/local/bin/mise`.

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
    "ghcr.io/bare-devcontainer/features/mise:latest": {}
}
```

The feature version is the mise version it installs. `:latest` resolves to the
newest feature release when the container is built; pin the exact version to hold
a mise release:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:2026.9.10": {}
}
```

## Installed software

- mise, the statically linked `linux-*-musl` build, installed as
  `/usr/local/bin/mise` and owned by root.

Nothing else: no tool is installed until the project asks for it.

## Tool installs and download cache

mise keeps its tool installs in `~/.local/share/mise` and its download cache in
`~/.cache/mise`, its own defaults. Both are created for the remote user when the
feature is installed.

Neither directory survives a rebuild on its own; see [Tips](#tips) for keeping
them on a volume.

## Not installed

- **No language runtime or tool.** mise resolves the versions the project declares.
- **No development headers beyond libc.** A backend that downloads prebuilt binaries
  works as-is; one that builds from source needs the `-dev` packages of the
  libraries it links against.
- **No `PATH` entry and no shell activation.** `mise exec` and `mise run` work as
  they are; see [Tips](#tips) for making tools resolve by name.

## Supply chain

The binary is downloaded from `https://github.com/jdx/mise/releases/` and checked
against `SHASUMS256.txt`, vendored with the feature: upstream's own checksum file,
committed verbatim together with the minisign signature upstream published for it.

The public key is a copy of
[`minisign.pub`](https://github.com/jdx/mise/blob/main/minisign.pub) from the mise
repository, refreshed by this repository's `Update Trusted Material` workflow.

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
- To keep the installed tools and the download cache across rebuilds, add named
  volumes to `mounts` in `devcontainer.json`, with the targets under the remote
  user's home directory:

  ```json
  "mounts": [
      {
          "source": "${devcontainerId}-mise-data",
          "target": "/home/dev/.local/share/mise",
          "type": "volume"
      },
      {
          "source": "${devcontainerId}-mise-cache",
          "target": "/home/dev/.cache/mise",
          "type": "volume"
      }
  ]
  ```
- To have tools resolve by name, put the shims directory in `remoteEnv` in
  `devcontainer.json`, with the path under the remote user's home directory:

  ```json
  "remoteEnv": {
      "PATH": "/home/dev/.local/share/mise/shims:${containerEnv:PATH}"
  }
  ```

  `mise activate` in the shell configuration covers interactive shells instead.
- [`MISE_PARANOID`](https://mise.jdx.dev/paranoid.html) in `containerEnv` makes mise
  re-verify the provenance of the tools it installs and refuse untrusted
  configuration.
- A rebuild clears which `mise.toml` files mise has trusted. Set
  `MISE_TRUSTED_CONFIG_PATHS` to the workspace folder in `containerEnv` to trust the
  project's up front.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bare-devcontainer/features/blob/main/src/mise/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
