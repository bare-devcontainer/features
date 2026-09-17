
# mise (mise)

Installs mise, the polyglot tool and runtime manager, from its GitHub release, verified against the mise minisign key, with its tool installs and download cache kept on volumes.

## Example Usage

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | mise version to install. Use "latest" for the newest release, or an exact version such as "2026.9.10". | string | latest |

The official release binary from [GitHub Releases](https://github.com/jdx/mise/releases)
is installed as `/usr/local/bin/mise`, and the directories mise installs tools into
and caches downloads in are placed on volumes the feature declares.

## Requirements

- A `linux-x64` or `linux-arm64` image. The glibc build is installed where the
  image's glibc is new enough to run it, and the statically linked musl build
  otherwise, so any Debian or Ubuntu release works.
- `wget` (or `curl`), `minisign`, `sha256sum` and a CA bundle, for the download and
  the signature check. Any of those the image is missing are installed with
  `apt-get`, so an image without them has to be Debian or Ubuntu based; an image
  that already has them needs no package manager at all.

## Usage

The defaults install the newest release. To pin a release instead:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/mise:1": {
        "version": "2026.9.10"
    }
}
```

`version` accepts `latest` or an exact version such as `2026.9.10`. `latest` is
resolved at install time, so a rebuild picks up newer releases.

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

The binary is downloaded from `https://github.com/jdx/mise/releases/`, and its
checksum is verified against `SHASUMS256.txt`, whose minisign signature is verified
with mise's public key. The key is vendored with the feature and read from there,
so the signature is checked against a key reviewed in this repository rather than
one fetched at install time. It is a copy of
[`minisign.pub`](https://github.com/jdx/mise/blob/main/minisign.pub) from the mise
repository, refreshed by this repository's `Update Trusted Material` workflow.

To see the key before pinning the feature:

```sh
cat src/mise/mise-minisign.pub
```

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
