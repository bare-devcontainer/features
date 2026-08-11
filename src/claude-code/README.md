
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

## Details

- Requires a Debian or Ubuntu based image.
- The repository signing key is vendored with the feature and installed to
  `/usr/share/keyrings/claude-code.asc`, so no key is downloaded at build time.
- The APT source is written to `/etc/apt/sources.list.d/claude-code.list`. Set
  `keepAptSource` to `false` to drop the source and key once installation
  finishes.

### VS Code extension

The feature also requests the Claude Code VS Code extension, so an editor that
attaches to the container gets the sidebar, inline diffs and the IDE
integration alongside the CLI:

```json
"customizations": {
    "vscode": {
        "extensions": [
            "anthropic.claude-code"
        ]
    }
}
```

Extension installation is done by the attaching client, not by the install
script, so this applies to VS Code, Cursor and GitHub Codespaces, and is
ignored by clients that do not consume `customizations.vscode` (the
`devcontainer` CLI, or attaching from another editor). The CLI is installed
either way. Nothing in `devcontainer.json` can remove an extension a feature
asks for, so uninstall it in the container if it is not wanted.

### Persisting configuration and credentials

Claude Code keeps its credentials, settings and history in its configuration
directory. The feature declares a volume mount so those survive container
rebuilds, and points Claude Code at it:

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


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bare-devcontainer/features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
