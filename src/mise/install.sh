#!/usr/bin/env bash
#
# Installs mise into /usr/local/bin from the official GitHub release. Both the
# version to install and the checksum to expect come from SHASUMS256.txt,
# vendored with the feature, so the download is verified with sha256sum alone
# and no signature tooling is installed into the container to check it.
#
# That file's authenticity is established in this repository rather than at
# install time: it is upstream's own checksum file, committed together with the
# minisign signature upstream published for it, and scripts/verify-material.sh
# checks the two against the vendored mise public key on every change.
#
# The directories mise installs tools into and caches downloads in are prepared
# for the remote user, at the paths the feature mounts volumes on and points
# MISE_DATA_DIR and MISE_CACHE_DIR at.
#
# This feature has no options: the vendored checksums cover one mise release,
# so the feature's own version is what selects which mise gets installed.
#
# Expected environment variables, from the Dev Container specification,
# injected by the CLI:
#
#   _REMOTE_USER       The account the container is attached as, and therefore
#                      the one mise installs tools as.

set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHASUMS="${FEATURE_DIR}/SHASUMS256.txt"
PREFIX="/usr/local"
RELEASES_URL="https://github.com/jdx/mise/releases"
# Coupled to containerEnv and mounts in devcontainer-feature.json.
DATA_DIR="/var/lib/mise"
CACHE_DIR="/var/cache/mise"
GROUP="mise"

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) This feature must be installed as root." >&2
    exit 1
fi

if [ ! -f "${SHASUMS}" ]; then
    echo "(!) ${SHASUMS} is missing; the feature cannot verify a download without it." >&2
    exit 1
fi

# Every download lands here, so nothing the install fetches is left in the
# image, whichever path the script exits by.
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# Debian package providing each command the installation needs.
package_for() {
    case "$1" in
        wget) echo "wget" ;;
        sha256sum) echo "coreutils" ;;
        *) echo "$1" ;;
    esac
}

# Installs whatever the base image is missing, and nothing it already has.
install_prerequisites() {
    local required=(sha256sum) missing=() cmd

    # Either downloader will do, so one is only pulled in when neither is there.
    if ! command -v curl >/dev/null 2>&1; then
        required+=(wget)
    fi

    for cmd in "${required[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("$(package_for "${cmd}")")
        fi
    done

    # HTTPS access to github.com needs a CA bundle.
    if [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
        missing+=(ca-certificates)
    fi

    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        echo "(!) Missing prerequisites and no apt-get to install them with: ${missing[*]}" >&2
        exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${missing[@]}"
    rm -rf /var/lib/apt/lists/*
}

download() {
    local url="$1" destination="$2"

    if command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -t 3 -O "${destination}" "${url}"
    else
        curl -fsSL --connect-timeout 30 --retry 3 -o "${destination}" "${url}"
    fi
}

# Reads the release to install out of the vendored checksums, which are the
# only place it is recorded: every entry names the release it belongs to, so
# the version cannot drift from the checksums the download is verified against.
pinned_version() {
    local versions count

    versions="$(grep -oE 'mise-v[0-9]{4}\.[0-9]+\.[0-9]+-' "${SHASUMS}" \
        | sed 's/^mise-//; s/-$//' \
        | sort -u)"
    count="$(printf '%s' "${versions}" | grep -c . || true)"

    if [ "${count}" -ne 1 ]; then
        echo "(!) ${SHASUMS} names ${count} mise versions; expected exactly one." >&2
        exit 1
    fi

    printf '%s\n' "${versions}"
}

mise_arch() {
    case "$(uname -m)" in
        x86_64) echo "x64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *)
            echo "(!) Unsupported architecture: $(uname -m)." >&2
            exit 1
            ;;
    esac
}

# Downloads the named release binary, checks it against the vendored checksums
# and installs it as ${PREFIX}/bin/mise.
install_binary() {
    local binary="$1" expected

    # Looked up before downloading, so a binary the vendored checksums do not
    # cover fails without fetching anything. Entries read "<sum>  ./<name>", and
    # the name is compared as a string so the dots in a version cannot act as
    # wildcards and match a neighbouring release.
    expected="$(awk -v name="./${binary}" '$2 == name { print $1 }' "${SHASUMS}")"
    if [ -z "${expected}" ]; then
        echo "(!) ${SHASUMS} has no checksum for ${binary}." >&2
        exit 1
    fi

    download "${RELEASES_URL}/download/${mise_version}/${binary}" "${tmpdir}/${binary}"
    printf '%s  %s\n' "${expected}" "${tmpdir}/${binary}" | sha256sum -c -

    install -m 755 "${tmpdir}/${binary}" "${PREFIX}/bin/mise"
}

# Runs the installed mise once, with every directory it might write to pointed
# into the temporary directory so the check leaves nothing behind.
mise_runs() {
    env HOME="${tmpdir}/home" \
        MISE_DATA_DIR="${tmpdir}/home/data" \
        MISE_CACHE_DIR="${tmpdir}/home/cache" \
        MISE_CONFIG_DIR="${tmpdir}/home/config" \
        MISE_STATE_DIR="${tmpdir}/home/state" \
        "${PREFIX}/bin/mise" --version
}

install_prerequisites

mise_version="$(pinned_version)"
arch="$(mise_arch)"

echo "Installing mise ${mise_version} (linux-${arch}) into ${PREFIX}/bin..."

# The glibc build is what upstream's installer picks on a glibc image, but a
# release can require a newer glibc than the image provides, in which case it
# fails to start at all. The statically linked musl build runs on any image, so
# it is installed in that case, verified against the same vendored checksums.
install_binary "mise-${mise_version}-linux-${arch}"
if ! output="$(mise_runs 2>&1)"; then
    echo "(*) The glibc build of mise ${mise_version} does not run on this image; installing the musl build instead." >&2
    echo "${output}" | sed 's/^/    /' >&2
    install_binary "mise-${mise_version}-linux-${arch}-musl"
    mise_runs >/dev/null
fi

username="${_REMOTE_USER:-root}"
if ! getent passwd "${username}" >/dev/null; then
    echo "(!) Remote user '${username}' was not found in the password database." >&2
    exit 1
fi

# The volumes are seeded from these directories on first use, ownership
# included, but the Dev Containers CLI renumbers the remote user to the host
# user's UID without touching anything outside the home directory. A dedicated
# group keeps the directories writable through that: membership is recorded by
# name, and the setgid bit keeps entries created later in the group.
if ! getent group "${GROUP}" >/dev/null; then
    groupadd --system "${GROUP}"
fi
usermod -aG "${GROUP}" "${username}"

mkdir -p "${DATA_DIR}" "${CACHE_DIR}"
chown "${username}:${GROUP}" "${DATA_DIR}" "${CACHE_DIR}"
chmod 2775 "${DATA_DIR}" "${CACHE_DIR}"

echo "Installed mise $("${PREFIX}/bin/mise" --version)."
