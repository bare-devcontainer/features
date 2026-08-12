# Bare Dev Container Features

[![CI](https://github.com/bare-devcontainer/features/actions/workflows/ci.yml/badge.svg)](https://github.com/bare-devcontainer/features/actions/workflows/ci.yml)

[Dev Container Features](https://containers.dev/features) for Debian and Ubuntu based
dev containers, published to `ghcr.io/bare-devcontainer/features`. Each Feature installs
a single tool from the upstream project's own distribution channel, verified against
signing material committed to this repository, and requires no other Feature.

## Features

| Feature | What you get | Source and verification |
|---------|--------------|-------------------------|
| [claude-code](src/claude-code)<br>`ghcr.io/bare-devcontainer/features/claude-code` | Claude Code, Anthropic's agentic coding CLI, with the VS Code extension requested alongside it. Credentials, settings and history live on a volume, so a rebuild does not mean signing in again. | Anthropic's APT repository. The package signature is checked with a key committed to this repository. |
| [node](src/node)<br>`ghcr.io/bare-devcontainer/features/node` | Node.js, with Corepack in place of npm, so the package manager comes from the project's `packageManager` field rather than from the image. | [nodejs.org](https://nodejs.org/dist/). The release checksums are checked against the Node.js release keys committed to this repository. |

Each Feature's README documents its options, requirements, what it deliberately leaves
out, and how its supply chain works.

## Why these features

A dev container is part of the trusted development environment, and every Feature added
to one installs software from another upstream. These Features are built so that adding
one stays reviewable, and so that a container can be rebuilt often — which is how
security updates arrive — without that becoming expensive:

- **Minimal trusted upstreams** — software comes from the upstream project's own
  distribution channel and nowhere else, verified with the method that upstream
  recommends.
- **Trusted material reviewed in this repository** — signing keys are committed here and
  changed only through a pull request, so nothing is fetched and trusted while the
  container is built. See [Supply chain](#supply-chain).
- **Self-contained installs** — no other Feature is required, only the prerequisites a
  base image turns out to be missing are installed, and nothing from the install is left
  behind in the image.
- **Minimal images stay minimal** — every Feature is installed and exercised on a
  minimal Debian image as well as on Microsoft's official base image on each change, so
  a Feature neither depends on tooling a larger image happens to carry nor drags such
  tooling in. See [Testing](#testing).
- **Fast, frequent rebuilds** — state a rebuild would otherwise discard, such as a
  tool's credentials and history, is kept in a named volume declared by the Feature, so
  rebuilding to pick up an update costs nothing but the build.

## Quick start

Add a Feature to `.devcontainer/devcontainer.json`, then reopen the project in a
container:

```json
{
  "image": "mcr.microsoft.com/devcontainers/base:debian",
  "features": {
    "ghcr.io/bare-devcontainer/features/node:1": {}
  }
}
```

Any [tool that supports dev containers](https://containers.dev/supporting) can install
them, onto any Debian or Ubuntu based image on `linux/amd64` or `linux/arm64`.
Requirements beyond that, such as glibc for a tool distributed as a prebuilt binary, are
stated in the Feature's own README.

Options are passed as the value of the reference. Each Feature's README lists the
options it accepts and their defaults:

```json
"features": {
  "ghcr.io/bare-devcontainer/features/node:1": {
    "version": "24",
    "keepNpm": true
  }
}
```

## Versions and pinning

Every release publishes four tags. Using version 1.1.1 as an example:

| Tag | Points at | Moves when |
|-----|-----------|------------|
| `1.1.1` | That exact release | Never |
| `1.1` | The newest 1.1.x release | A patch release is published |
| `1` | The newest 1.x release | A minor or patch release is published |
| `latest` | The newest release | Any release |

A reference is resolved when the container is built, so any tag shorter than the exact
version resolves to different content over time. That is how `:1` picks up fixes
automatically, and also why it is not a reproducible reference on its own — commit
`.devcontainer/devcontainer-lock.json` to record the digest it resolved to.

## Supply chain

**What you are trusting.** The upstream distribution channel listed for the Feature in
the table above, and the contents of this repository at the version you pin. Nothing
else takes part in the install: the signing material is read from the Feature itself, so
no key is fetched while the container is built, and no other Feature's install script
runs on its behalf.

**What you can check before pinning.** Every input is a file in this repository: one
install script per Feature, and the signing material sitting next to it. Each Feature's
README shows how to inspect its key.

**How the trusted material changes.** Only through a pull request. The
`Update Trusted Material` workflow
([`.github/workflows/update-material.yml`](.github/workflows/update-material.yml)) checks
upstream weekly and opens one when a key has changed, so every rotation is visible in
the history of this repository rather than picked up silently at build time.

**What is not covered.** The upstream projects themselves are still trusted: verification
proves a download came from them unaltered, not that what they published is sound. These
Features are published as plain OCI artifacts, with no SLSA provenance attestation and no
SBOM. And a floating tag still resolves to whatever is newest — see
[Versions and pinning](#versions-and-pinning).

## Testing

Every Feature ships a `smoke_test.sh` next to its `devcontainer-feature.json`. On every
change, the `CI` workflow ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))
installs each Feature at its default options on
`mcr.microsoft.com/devcontainers/base:debian`, the official Dev Container base image
from Microsoft, and on `ghcr.io/bare-devcontainer/debian:trixie`, a minimal Debian image
with no `sudo`, no alternative shell and no CLI tooling beyond the basics, then runs
that script inside the running container as the remote user.

The scripts use no test helper library, so each one reads as a plain description of what
a successful install looks like.

## Related repositories

- [bare-devcontainer/images](https://github.com/bare-devcontainer/images) — minimal
  Debian based dev container images, one per language stack. When the base image can be
  chosen freely, an image that already carries the tool is simpler than adding a
  Feature.
- [bare-devcontainer/templates](https://github.com/bare-devcontainer/templates) —
  `devcontainer.json` templates for those images, with hardened defaults and cache
  volumes. Features can be added to a template's configuration after it is applied.

## Contributing

Bug reports, Feature requests and pull requests are welcome. [AGENTS.md](AGENTS.md)
describes the repository layout and the conventions a change is expected to follow.

Note that `src/*/README.md` is generated by `devcontainer features generate-docs` from
`devcontainer-feature.json` and the Feature's `NOTES.md`. Put prose in `NOTES.md`; edits
made directly to a Feature's `README.md` are overwritten.

## Security

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
