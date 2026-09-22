#!/usr/bin/env bash
#
# Installs mise into /usr/local/bin from the official GitHub release. The
# release to install and the checksum to expect both come from SHASUMS256.txt,
# vendored with the feature; scripts/verify-material.sh checks its signature.
#
# Expected environment variables, from the Dev Container specification,
# injected by the CLI:
#
#   _REMOTE_USER       The account the container is attached as.
#   _REMOTE_USER_HOME  That account's home directory.

set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHASUMS="${FEATURE_DIR}/SHASUMS256.txt"
PREFIX="/usr/local"
RELEASES_URL="https://github.com/jdx/mise/releases"

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) This feature must be installed as root." >&2
    exit 1
fi

if [ ! -f "${SHASUMS}" ]; then
    echo "(!) ${SHASUMS} is missing; the feature cannot verify a download without it." >&2
    exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

package_for() {
    case "$1" in
        wget) echo "wget" ;;
        sha256sum) echo "coreutils" ;;
        *) echo "$1" ;;
    esac
}

install_prerequisites() {
    local required=(sha256sum) missing=() cmd

    # Either downloader will do, so wget is only pulled in when curl is absent.
    if ! command -v curl >/dev/null 2>&1; then
        required+=(wget)
    fi

    for cmd in "${required[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("$(package_for "${cmd}")")
        fi
    done

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

    # Only the lists this script's apt-get update fetched are removed; an image
    # that ships its own means them to be kept. "lock" and "partial" do not count.
    local lists_shipped=false
    if find /var/lib/apt/lists -maxdepth 1 -type f ! -name lock -print -quit 2>/dev/null \
        | grep -q .; then
        lists_shipped=true
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${missing[@]}"

    if [ "${lists_shipped}" = false ]; then
        rm -rf /var/lib/apt/lists/*
    fi
}

download() {
    local url="$1" destination="$2"

    if command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -t 3 -O "${destination}" "${url}"
    else
        curl -fsSL --connect-timeout 30 --retry 3 -o "${destination}" "${url}"
    fi
}

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

install_binary() {
    local binary="$1" expected

    # Entries read "<sum>  ./<name>". The name is compared as a string so the
    # dots in a version cannot act as wildcards and match a neighbouring release.
    expected="$(awk -v name="./${binary}" '$2 == name { print $1 }' "${SHASUMS}")"
    if [ -z "${expected}" ]; then
        echo "(!) ${SHASUMS} has no checksum for ${binary}." >&2
        exit 1
    fi

    download "${RELEASES_URL}/download/${mise_version}/${binary}" "${tmpdir}/${binary}"
    printf '%s  %s\n' "${expected}" "${tmpdir}/${binary}" | sha256sum -c -

    install -m 755 "${tmpdir}/${binary}" "${PREFIX}/bin/mise"
}

# Every directory mise might write to is pointed into the temporary directory,
# so running it here leaves nothing in the image.
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

echo "Installing mise ${mise_version} (linux-${arch}-musl) into ${PREFIX}/bin..."

# The musl build is statically linked, so it runs whatever the image's glibc
# version is. The glibc build does not, and a release can require a newer glibc
# than the image provides.
install_binary "mise-${mise_version}-linux-${arch}-musl"
mise_runs >/dev/null

username="${_REMOTE_USER:-root}"
if ! getent passwd "${username}" >/dev/null; then
    echo "(!) Remote user '${username}' was not found in the password database." >&2
    exit 1
fi
home="${_REMOTE_USER_HOME:-$(getent passwd "${username}" | cut -d: -f6)}"
group="$(id -gn "${username}")"

# Created rather than left to mise, so a volume mounted over one is seeded with
# this owner. The parents are listed too, or root keeps the rest of ~/.local
# and ~/.cache.
install -d -o "${username}" -g "${group}" \
    "${home}/.local" "${home}/.local/share" "${home}/.local/share/mise" \
    "${home}/.cache" "${home}/.cache/mise"

echo "Installed mise $("${PREFIX}/bin/mise" --version)."
