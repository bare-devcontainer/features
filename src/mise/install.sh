#!/usr/bin/env bash
#
# Installs mise into /usr/local/bin from the official GitHub release, mirroring
# the setup of the ghcr.io/bare-devcontainer/mise image: the release binary is
# checked against SHASUMS256.txt, whose minisign signature is verified with the
# vendored mise public key. The directories mise installs tools into and caches
# downloads in are prepared for the remote user, at the paths the feature
# mounts volumes on and points MISE_DATA_DIR and MISE_CACHE_DIR at.
#
# Expected environment variables, from this feature's own options:
#
#   VERSION            mise version to install: "latest", or an exact version
#                      such as "2026.9.10".
#
# and from the Dev Container specification, injected by the CLI:
#
#   _REMOTE_USER       The account the container is attached as, and therefore
#                      the one mise installs tools as.

set -euo pipefail

VERSION="${VERSION:-latest}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_KEY="${FEATURE_DIR}/mise-minisign.pub"
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

# Every download lands here, so nothing the install fetches is left in the
# image, whichever path the script exits by.
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# Debian package providing each command the installation needs.
package_for() {
    case "$1" in
        wget) echo "wget" ;;
        minisign) echo "minisign" ;;
        sha256sum) echo "coreutils" ;;
        *) echo "$1" ;;
    esac
}

# Installs whatever the base image is missing, and nothing it already has.
install_prerequisites() {
    local required=(minisign sha256sum) missing=() cmd

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

# Prints the Location header a URL redirects to, without following it.
redirect_target() {
    local url="$1"

    if command -v wget >/dev/null 2>&1; then
        # wget treats the redirect it was told not to follow as a failure, but
        # has printed the response headers by then.
        (wget -q -T 30 -t 3 --max-redirect=0 -S -O /dev/null "${url}" 2>&1 || true) \
            | sed -n 's/^ *Location: *//p' | head -n1
    else
        curl -fsSI --connect-timeout 30 --retry 3 -o /dev/null -w '%{redirect_url}' "${url}"
    fi
}

# Turns the requested version into the exact "vYYYY.M.N" the release is
# published under. "latest" is resolved through the redirect GitHub serves for
# a repository's latest release, which lands on that release's tag page.
resolve_version() {
    local requested="${1#v}" location resolved

    if [[ "${requested}" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]]; then
        echo "v${requested}"
        return
    fi

    if [ "${requested}" != "latest" ]; then
        echo "(!) Unrecognised version '$1'. Use \"latest\" or an exact version such as \"2026.9.10\"." >&2
        exit 1
    fi

    location="$(redirect_target "${RELEASES_URL}/latest")"
    resolved="${location##*/tag/}"

    if [ -z "${location}" ] || [[ ! "${resolved}" =~ ^v[0-9]{4}\.[0-9]+\.[0-9]+$ ]]; then
        echo "(!) Could not resolve the latest mise release from ${RELEASES_URL}/latest (got '${location}')." >&2
        exit 1
    fi

    echo "${resolved}"
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

# Downloads the named release binary, checks it against the verified
# SHASUMS256.txt and installs it as ${PREFIX}/bin/mise.
install_binary() {
    local binary="$1"

    download "${RELEASES_URL}/download/${mise_version}/${binary}" "${tmpdir}/${binary}"

    # SHASUMS256.txt names each file as ./<name>, so the entry is rewritten to
    # point at the copy just downloaded.
    grep "  \\./${binary}\$" "${tmpdir}/SHASUMS256.txt" \
        | sed "s|  \\./${binary}\$|  ${tmpdir}/${binary}|" \
        | sha256sum -c -

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

mise_version="$(resolve_version "${VERSION}")"
arch="$(mise_arch)"

echo "Installing mise ${mise_version} (linux-${arch}) into ${PREFIX}/bin..."
download "${RELEASES_URL}/download/${mise_version}/SHASUMS256.txt" "${tmpdir}/SHASUMS256.txt"
download "${RELEASES_URL}/download/${mise_version}/SHASUMS256.txt.minisig" "${tmpdir}/SHASUMS256.txt.minisig"

# The checksums are signed with mise's minisign key. The public key is vendored
# with the feature, so the signature is checked against the key reviewed in
# this repository rather than one fetched at install time.
minisign -V -m "${tmpdir}/SHASUMS256.txt" -p "${PUBLIC_KEY}"

# The glibc build is what upstream's installer picks on a glibc image, but a
# release can require a newer glibc than the image provides, in which case it
# fails to start at all. The statically linked musl build runs on any image, so
# it is installed in that case, verified against the same signed checksums.
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
