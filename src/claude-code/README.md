
# Claude Code (claude-code)

Installs Claude Code, Anthropic's agentic coding CLI, from the official APT repository.

## Example Usage

```json
"features": {
    "ghcr.io/bare-devcontainer/features/claude-code:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | APT package version of claude-code to install. Use "latest" for the newest available version, or an exact version string as reported by `apt-cache policy claude-code`. | string | latest |
| keepAptSource | Keep the Claude Code APT source and signing key in the image so the package can be upgraded later. When false, both are removed after installation. | boolean | true |

## Customizations

### VS Code Extensions

- `anthropic.claude-code`

## Requirements

- A Debian or Ubuntu based image: the package is installed with `apt-get`, and the
  install script stops early on an image without it.

## Usage

The defaults install the newest package and leave the APT source in place. To drop
the source and its key once the package is installed:

```json
"features": {
    "ghcr.io/bare-devcontainer/features/claude-code:1": {
        "keepAptSource": false
    }
}
```

`version` takes an APT package version rather than a release name, so read the exact
string off `apt-cache policy claude-code` in a container that has the source
configured before pinning to one.

## Installed software

- The `claude` CLI, from Anthropic's APT repository at
  `https://downloads.claude.ai/claude-code/apt/stable`. The source is written to
  `/etc/apt/sources.list.d/claude-code.list` and the signing key to
  `/usr/share/keyrings/claude-code.asc`.
- The Claude Code VS Code extension (`anthropic.claude-code`), installed by clients
  that read `customizations.vscode`.

To leave the extension out, list it with a minus sign in `devcontainer.json`:

```json
"customizations": {
    "vscode": {
        "extensions": [
            "-anthropic.claude-code"
        ]
    }
}
```

## Configuration and credentials

Claude Code keeps its credentials, settings and history in its configuration
directory. The feature declares a volume mount so those survive container rebuilds,
and points Claude Code at it:

```json
"containerEnv": {
    "CLAUDE_CONFIG_DIR": "/var/lib/claude-code"
},
"mounts": [
    {
        "source": "${devcontainerId}-claude-code-config",
        "target": "/var/lib/claude-code",
        "type": "volume"
    }
]
```

A feature's mount target is static and cannot reference the remote user's home
directory, so the volume is mounted at `/var/lib/claude-code` and
`CLAUDE_CONFIG_DIR` moves the configuration directory there. That keeps the
mount working whatever the image uses as its remote user, and covers
`.claude.json` (onboarding state, the logged-in account, project history and
user-scoped MCP servers) as well as `~/.claude` would have.

Anything already present in `~/.claude` when the feature runs — from the base
image or an earlier feature — is copied into `/var/lib/claude-code`, but only
when the volume has not been seeded yet. The original is left in place, since a
pre-existing volume masks the copy at run time.

`containerEnv` from `devcontainer.json` takes precedence over a feature's, so
setting `CLAUDE_CONFIG_DIR` there points Claude Code somewhere else and leaves
the volume unused.

The named volume is seeded from the image on first use, ownership included. The
Dev Containers CLI renumbers the remote user to the host user's UID and GID on
Linux, but only chowns the home directory, so a directory owned by a build-time
UID would end up unreachable. The install script therefore creates a
`claude-code` system group, adds the remote user to it, and makes
`/var/lib/claude-code` group-writable and setgid: group membership is recorded by
name and is unaffected by the renumbering.

One case is not covered. If an existing volume is reused after the host user's
UID changed, files written under the old UID keep their owner-only modes and
Claude Code cannot rewrite them; clear them with `rm -rf /var/lib/claude-code/*`
(this drops stored credentials and history) or remove the volume. Files created
afterwards are unaffected.

The volume is per dev container (`${devcontainerId}`) and is not shared between
projects. Mounts declared by a feature cannot be disabled from
`devcontainer.json`, but overriding `CLAUDE_CONFIG_DIR` as shown above leaves the
volume mounted and unused.

## Supply chain

The package is installed by APT from Anthropic's official repository, and its
signature is checked against the repository signing key. That key is vendored with
the feature and installed from the feature directory to
`/usr/share/keyrings/claude-code.asc`, so nothing is trusted that was not reviewed
in this repository — no key is downloaded at build time. It is refreshed by this
repository's `Update Trusted Material` workflow, which opens a pull request when
upstream publishes a different key.

To see the key before pinning the feature:

```sh
gpg --show-keys src/claude-code/claude-code.asc
```

`keepAptSource` decides what is left behind. Keeping the source and key, the
default, means `apt-get upgrade` inside the container can pick up newer releases.
Setting it to `false` removes both once the install finishes, so the image carries
no additional APT source. Either way the apt lists downloaded during installation
are deleted.

## Tips

- For the tags this feature is published under, see
  [Versions and pinning](https://github.com/bare-devcontainer/features#versions-and-pinning).
- The configuration volume is per dev container, so authentication is done once per
  project. Point `CLAUDE_CONFIG_DIR` at a mount of your own to share credentials
  between projects.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bare-devcontainer/features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
