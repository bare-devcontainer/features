#!/usr/bin/env bash
#
# Installs the Claude Code CLI from Anthropic's official APT repository and
# prepares the remote user's configuration directory (~/.claude).
#
# Expected environment variables, from this feature's own options:
#
#   VERSION            APT package version to install, or "latest".
#   KEEPAPTSOURCE      "true" to leave the APT source and signing key in the
#                      image.
#
# and from the Dev Container specification, injected by the CLI:
#
#   _REMOTE_USER       The account the container is attached as, and therefore
#                      the one Claude Code reads its configuration as.
#   _REMOTE_USER_HOME  Home directory of _REMOTE_USER.

set -euo pipefail

VERSION="${VERSION:-latest}"
KEEPAPTSOURCE="${KEEPAPTSOURCE:-true}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_KEYRING="/usr/share/keyrings/claude-code.asc"
APT_SOURCE="/etc/apt/sources.list.d/claude-code.list"
APT_REPOSITORY="https://downloads.claude.ai/claude-code/apt/stable stable main"

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) This feature must be installed as root." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "(!) This feature requires a Debian/Ubuntu based image (apt-get not found)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# The APT repository is served over HTTPS, which fails on minimal images that
# ship without a CA bundle.
if [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates
fi

# The signing key is vendored with the feature so installation does not depend
# on fetching a key over the network at build time.
install -m 0644 "${FEATURE_DIR}/claude-code.asc" "${APT_KEYRING}"
echo "deb [signed-by=${APT_KEYRING}] ${APT_REPOSITORY}" > "${APT_SOURCE}"

# Index the source added above.
apt-get update -y

if [ "${VERSION}" = "latest" ] || [ -z "${VERSION}" ]; then
    package="claude-code"
else
    package="claude-code=${VERSION}"
fi
apt-get install -y --no-install-recommends "${package}"

if [ "${KEEPAPTSOURCE}" != "true" ]; then
    rm -f "${APT_SOURCE}" "${APT_KEYRING}"
fi

rm -rf /var/lib/apt/lists/*

# Claude Code stores credentials, settings and history under ~/.claude. The
# feature mounts a volume at CONFIG_DIR and ~/.claude is linked to it, so the
# configuration survives rebuilds. The volume target cannot depend on the remote
# user's home directory (feature mounts are static), hence the indirection.
USERNAME="${_REMOTE_USER:-root}"
USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "${USERNAME}" | cut -d: -f6)}"
USER_GROUP="$(id -gn "${USERNAME}")"
CONFIG_DIR="/var/lib/claude-code"

# A named volume is seeded from the image on first use, so creating the
# directory with the right ownership here also makes the volume itself owned by
# the remote user.
mkdir -p "${CONFIG_DIR}"
chown "${USERNAME}:${USER_GROUP}" "${CONFIG_DIR}"

if [ -n "${USER_HOME}" ]; then
    config_link="${USER_HOME}/.claude"
    if [ -d "${config_link}" ] && [ ! -L "${config_link}" ]; then
        # Preserve whatever the base image or an earlier feature put there.
        cp -a "${config_link}/." "${CONFIG_DIR}/"
        rm -rf "${config_link}"
    else
        rm -f "${config_link}"
    fi
    ln -s "${CONFIG_DIR}" "${config_link}"
    chown -h "${USERNAME}:${USER_GROUP}" "${config_link}"
fi

echo "Installed $(claude --version 2>/dev/null || echo 'claude-code')."
