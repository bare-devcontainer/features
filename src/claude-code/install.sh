#!/usr/bin/env bash
#
# Installs the Claude Code CLI from Anthropic's official APT repository and
# prepares the configuration directory the feature points CLAUDE_CONFIG_DIR at.
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

# Ensure the system has a CA bundle for HTTPS access to the APT repository.
if [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates
fi

# Add the official Claude Code apt repository.
install -D -m 0644 "${FEATURE_DIR}/claude-code.asc" "${APT_KEYRING}"
echo "deb [signed-by=${APT_KEYRING}] ${APT_REPOSITORY}" > "${APT_SOURCE}"
apt-get update -y

# Install the requested version of the package, or the latest if none was specified.
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

USERNAME="${_REMOTE_USER:-root}"
CONFIG_DIR="/var/lib/claude-code"
CONFIG_GROUP="claude-code"

if ! passwd_entry="$(getent passwd "${USERNAME}")"; then
    echo "(!) Remote user '${USERNAME}' was not found in the password database." >&2
    exit 1
fi

# Create a dedicated group for the configuration directory, and add the remote user to it.
# This allows the remote user to access the configuration directory even if the remote user's UID is renumbered by `updateRemoteUserUID` option.
mkdir -p "${CONFIG_DIR}"
if ! getent group "${CONFIG_GROUP}" >/dev/null; then
    groupadd --system "${CONFIG_GROUP}"
fi
usermod -aG "${CONFIG_GROUP}" "${USERNAME}"

# Transfer any existing configuration from the remote user's home directory to the mounted volume if it exists.
USER_HOME="${_REMOTE_USER_HOME:-$(printf '%s' "${passwd_entry}" | cut -d: -f6)}"
if [ -n "${USER_HOME}" ] && [ -d "${USER_HOME}/.claude" ] && [ -z "$(ls -A "${CONFIG_DIR}")" ]; then
    cp -a "${USER_HOME}/.claude/." "${CONFIG_DIR}/"
fi

# Set the ownership and permissions of the configuration directory.
# The setgid bit keeps entries created later in the shared group.
chown -R "${USERNAME}:${CONFIG_GROUP}" "${CONFIG_DIR}"
chmod -R g+rwX "${CONFIG_DIR}"
chmod 2775 "${CONFIG_DIR}"

echo "Installed $(claude --version 2>/dev/null || echo 'claude-code')."
