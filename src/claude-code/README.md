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
| version | APT package version of claude-code to install. Use `latest` for the newest available version, or an exact version string as reported by `apt-cache policy claude-code`. | string | latest |
| keepAptSource | Keep the Claude Code APT source and signing key in the image so the package can be upgraded later. When false, both are removed after installation. | boolean | true |

## Details

- Requires a Debian or Ubuntu based image.
- The repository signing key is vendored with the feature and installed to
  `/usr/share/keyrings/claude-code.asc`, so no key is downloaded at build time.
- The APT source is written to `/etc/apt/sources.list.d/claude-code.list`. Set
  `keepAptSource` to `false` to drop the source and key once installation
  finishes.
### Persisting configuration and credentials

Claude Code keeps its credentials, settings and history under `~/.claude`. The
feature declares a volume mount so those survive container rebuilds:

```json
"mounts": [
    {
        "source": "${devcontainerId}-claude-code-config",
        "target": "/var/lib/claude-code",
        "type": "volume"
    }
]
```

A feature's mount target is static and cannot reference the remote user's home
directory, so the volume is mounted at `/var/lib/claude-code` and the install
script links `~/.claude` to it. That keeps the mount working whatever the image
uses as its remote user. The directory is created and owned by the remote user
at build time, which is also the ownership the named volume is seeded with on
first use.

The volume is per dev container (`${devcontainerId}`) and is not shared between
projects. Mounts declared by a feature cannot be disabled from `devcontainer.json`;
if you need different storage, point `~/.claude` elsewhere via the
`CLAUDE_CONFIG_DIR` environment variable.
