
# mise (mise)

Installs mise, the polyglot tool and runtime manager, from its GitHub release, verified against checksums committed to this repository, with its tool installs and download cache kept on volumes.

## Example Usage

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1": {}
}
```



The official release binary from [GitHub Releases](https://github.com/jdx/mise/releases)
is installed as `/usr/local/bin/mise`, and the directories mise installs tools into
and caches downloads in are placed on volumes the feature declares.

## Requirements

- A `linux-x64` or `linux-arm64` image. The glibc build is installed where the
  image's glibc is new enough to run it, and the statically linked musl build
  otherwise, so any Debian or Ubuntu release works.
- `wget` (or `curl`), `sha256sum` and a CA bundle, for the download and the checksum
  check. Any of those the image is missing are installed with `apt-get`, so an image
  without them has to be Debian or Ubuntu based; an image that already has them
  needs no package manager at all, and in practice that is every image with a
  downloader. Nothing is installed in order to verify the download — see
  [Supply chain](#supply-chain).

## Usage

The feature takes no options:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1": {}
}
```

Which mise release gets installed is decided by the checksums committed with the
feature, so the feature's own version is what selects it. Pin the reference to hold
a release, and read the release notes to see which mise a version carries:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1.0.0": {}
}
```

A shorter tag such as `:1` resolves to the newest release when the container is
built, so it picks up newer mise releases on a rebuild. See
[Versions and pinning](https://github.com/bare-devcontainer/features#versions-and-pinning).

Not every project needs this feature: on the
[`ghcr.io/bare-devcontainer/mise`](https://github.com/bare-devcontainer/images/tree/main/mise)
image, mise is already there. The feature is for adding mise to any other image, such
as a language image that needs a second toolchain or a linter the project pins.

## Installed software

- mise, installed as `/usr/local/bin/mise`, owned by root.

Nothing else: no tool is installed until the project asks for it. `mise install`
installs everything a project's `mise.toml` declares, and `mise exec <tool>@<version>
-- <cmd>` runs a one-off without declaring anything. To install the project's tools
when the container is created rather than on first use, run `mise install` from a
`postCreateCommand`.

The shims directory is on `PATH`, so a tool resolves as soon as mise installs it,
for editors and other programs that do not load the shell configuration as well as
in the terminal. `mise activate` can be added to the shell configuration for the
[features shims do not cover](https://mise.jdx.dev/dev-tools/shims.html), such as
environment variables declared in `mise.toml`.

## Tool installs and download cache

mise keeps its tool installs in `MISE_DATA_DIR` and its download cache in
`MISE_CACHE_DIR`. The feature declares a volume for each, so a rebuild neither
reinstalls the tools nor downloads them again, and points mise at them:

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

A feature's mount target is static and cannot reference the remote user's home
directory, so the volumes are mounted under `/var` and the environment variables
move the directories there. That keeps the mounts working whatever the image uses
as its remote user. The shims directory moves with `MISE_DATA_DIR`, which is why
`PATH` names it under `/var/lib/mise`.

The volumes are seeded from the image on first use, ownership included. The Dev
Containers CLI renumbers the remote user to the host user's UID and GID on Linux,
but only chowns the home directory, so a directory owned by a build-time UID would
end up unreachable. The install script therefore creates a `mise` system group,
adds the remote user to it, and makes both directories group-writable and setgid:
group membership is recorded by name and is unaffected by the renumbering.

One case is not covered. If an existing volume is reused after the host user's UID
changed, files written under the old UID keep their owner-only modes and mise cannot
replace them; clear them with `rm -rf /var/lib/mise/* /var/cache/mise/*` (this
removes the installed tools) or remove the volumes. Files created afterwards are
unaffected.

The volumes are per dev container (`${devcontainerId}`) and are not shared between
projects. Mounts declared by a feature cannot be disabled from `devcontainer.json`,
but `containerEnv` there takes precedence over a feature's, so setting
`MISE_DATA_DIR` or `MISE_CACHE_DIR` points mise somewhere else and leaves the volume
mounted and unused. `PATH` then needs the new shims directory as well.

mise's configuration (`~/.config/mise`) and state, including which `mise.toml`
files have been trusted (`~/.local/state/mise`), stay in the remote user's home
directory and are recreated by a rebuild.

## Not installed

- **No language runtime or tool.** mise resolves the versions the project declares
  in `mise.toml` or in idiomatic per-language files such as `.node-version`.
- **No development headers beyond libc.** A backend that downloads prebuilt
  binaries works as-is; one that builds a runtime from source needs the `-dev`
  packages of the libraries it links against.
- **No shell activation.** The shell configuration is left untouched; the shims
  directory on `PATH` is what makes installed tools resolve.

## Supply chain

The binary is downloaded from `https://github.com/jdx/mise/releases/` and checked
against `SHASUMS256.txt`, which is vendored with the feature. That file is
upstream's own checksum file, committed verbatim together with the minisign
signature upstream published for it, so the expected hash of every release binary
is a reviewed line in this repository rather than something fetched while the
container is built.

Checking the download therefore needs `sha256sum` and nothing else. The signature
is verified where the tooling for it is free rather than in the container: the
`CI` workflow runs
[`scripts/verify-material.sh`](https://github.com/bare-devcontainer/features/blob/main/scripts/verify-material.sh)
on every change, which checks `SHASUMS256.txt` against `SHASUMS256.txt.minisig`
using the vendored public key. A hand-edited checksum fails that job, and an
install can never be talked into skipping it, because the install has no signature
step to skip.

The public key is a copy of
[`minisign.pub`](https://github.com/jdx/mise/blob/main/minisign.pub) from the mise
repository, refreshed by this repository's `Update Trusted Material` workflow. The
checksums move only when the pinned release does:
[`scripts/pin-checksums.sh`](https://github.com/bare-devcontainer/features/blob/main/scripts/pin-checksums.sh)
re-pins them to a named release and writes what it downloaded only once the signature
verifies, so a newer mise reaches this feature through a pull request that bumps the
feature version alongside the checksums.

To check the material yourself before pinning the feature:

```sh
cat src/mise/mise-minisign.pub
minisign -V -m src/mise/SHASUMS256.txt \
    -x src/mise/SHASUMS256.txt.minisig \
    -p src/mise/mise-minisign.pub
```

Because the checksums cover one release, the version they pin is the version the
feature installs; `grep linux-x64 src/mise/SHASUMS256.txt` shows which.

This covers the mise binary only. Tools that mise installs at runtime are fetched
from their own upstreams under mise's own verification, which
[`MISE_PARANOID`](https://mise.jdx.dev/paranoid.html) makes stricter.

Everything downloaded during installation goes to a temporary directory that is
removed when the script exits.

## Tips

- For the tags this feature is published under, see
  [Versions and pinning](https://github.com/bare-devcontainer/features#versions-and-pinning).
- To have mise re-verify the provenance of the tools it installs on every install
  and refuse untrusted configuration, set `MISE_PARANOID` in `containerEnv`:

  ```json
  "containerEnv": {
      "MISE_PARANOID": "1"
  }
  ```

- The project's `mise.toml` has to be trusted before mise reads it, and a rebuild
  clears that trust. Set `MISE_TRUSTED_CONFIG_PATHS` to the workspace folder in
  `containerEnv` to trust it up front.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bare-devcontainer/features/blob/main/src/mise/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
