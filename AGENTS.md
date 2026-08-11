# Repository Guidelines

This repository publishes dev container features for use with the [Dev Containers specification](https://containers.dev/), published to `ghcr.io/bare-devcontainer/features`.

- Use English for all documentation and comments.
- Comments should follow either of the following types:
  - Documentation comments: describe the purpose/signature of a file, function, or block of code.
  - Inline comments: describe the important details of a line or block of code for future maintainers. Avoid obvious comments, or comments only useful in the context of the current change.
- PR titles must follow Conventional Commits format:
  - Allowed types: `image`, `ci`, `chore`, `test`, `docs`
  - The scope is optional. Examples:
    - `feature(node): add Node.js 26 variant`
    - `ci: pin action SHAs`
    - `chore: update renovate config`

## GitHub Actions

- Pin every action to a full commit SHA with a `# vX.Y.Z` comment,
  e.g. `uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0`.
- Set workflow-level permissions to empty (`permissions: {}`) and grant
  the minimum required permissions per job.
- Set `persist-credentials: false` on `actions/checkout`.
