#!/usr/bin/env bash
#
# Installs Node.js into /usr/local from the official nodejs.org distribution,
# mirroring the setup of the ghcr.io/bare-devcontainer/node image: the release
# tarball is checked against the signed SHASUMS256.txt.asc using the vendored
# Node.js release keyring, Corepack is installed from npm, and npm itself is
# removed afterwards.
#
# Expected environment variables, from this feature's own options:
#
#   VERSION            Node.js version to install: "lts", "latest", a release
#                      line such as "24" or "24.19", or an exact version.
#   COREPACK           npm version specifier of Corepack to install, or "none".
#   KEEPNPM            "true" to leave npm and npx in place.
#
# and from the Dev Container specification, injected by the CLI:
#
#   _REMOTE_USER       The account the container is attached as, and therefore
#                      the one Corepack caches package managers for.
#   _REMOTE_USER_HOME  Home directory of _REMOTE_USER.

set -euo pipefail

VERSION="${VERSION:-lts}"
COREPACK="${COREPACK:-latest}"
KEEPNPM="${KEEPNPM:-false}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYRING="${FEATURE_DIR}/node-keyring.kbx"
PREFIX="/usr/local"
DIST_URL="https://nodejs.org/dist"

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
        gpgv) echo "gpgv" ;;
        tar) echo "tar" ;;
        xz) echo "xz-utils" ;;
        sha256sum) echo "coreutils" ;;
        *) echo "$1" ;;
    esac
}

# Installs whatever the base image is missing, and nothing it already has.
install_prerequisites() {
    local required=(gpgv tar xz sha256sum) missing=() cmd

    # Either downloader will do, so one is only pulled in when neither is there.
    if ! command -v curl >/dev/null 2>&1; then
        required+=(wget)
    fi

    for cmd in "${required[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("$(package_for "${cmd}")")
        fi
    done

    # HTTPS access to nodejs.org needs a CA bundle.
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

# Turns the requested version into the exact "vX.Y.Z" the distribution is
# published under. Releases in index.json are ordered newest first, so the
# first entry matching a selector is the newest release it covers.
resolve_version() {
    local requested="${1#v}" selector index entries resolved

    if [[ "${requested}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "v${requested}"
        return
    fi

    case "${requested}" in
        latest) selector='"version":"v' ;;
        # Only long-term support releases carry a codename; the rest are false.
        lts) selector='"lts":"' ;;
        *)
            if [[ ! "${requested}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                echo "(!) Unrecognised version '$1'. Use \"lts\", \"latest\", a release line such as \"24\" or \"24.19\", or an exact version." >&2
                exit 1
            fi
            selector="\"version\":\"v${requested}."
            ;;
    esac

    index="${tmpdir}/index.json"
    entries="${tmpdir}/releases.txt"
    download "${DIST_URL}/index.json" "${index}"

    # Matching is per line, which is how nodejs.org serves the index: one
    # release object per line, without spaces around the separators. The sed
    # covers the array arriving on a single line instead; any other layout ends
    # in the no-match error below rather than a wrong version. The intermediate
    # file keeps grep's early exit from ending the split with a broken pipe.
    sed 's/},[[:space:]]*{/}\n{/g' "${index}" > "${entries}"
    resolved="$(grep -m1 -F "${selector}" "${entries}" | sed -n 's/.*"version":"\(v[^"]*\)".*/\1/p' || true)"

    if [ -z "${resolved}" ]; then
        echo "(!) No Node.js release matches '$1'." >&2
        exit 1
    fi

    echo "${resolved}"
}

node_arch() {
    case "$(uname -m)" in
        x86_64) echo "x64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *)
            echo "(!) Unsupported architecture: $(uname -m)." >&2
            exit 1
            ;;
    esac
}

install_prerequisites

node_version="$(resolve_version "${VERSION}")"
arch="$(node_arch)"
tarball="node-${node_version}-linux-${arch}.tar.xz"

echo "Installing Node.js ${node_version} (linux-${arch}) into ${PREFIX}..."
download "${DIST_URL}/${node_version}/${tarball}" "${tmpdir}/${tarball}"
download "${DIST_URL}/${node_version}/SHASUMS256.txt.asc" "${tmpdir}/SHASUMS256.txt.asc"

# The checksums are signed by the Node.js Release Team. The keyring is vendored
# with the feature, so the keys are the ones reviewed in this repository rather
# than keys fetched at install time.
gpgv --keyring "${KEYRING}" --output "${tmpdir}/SHASUMS256.txt" < "${tmpdir}/SHASUMS256.txt.asc"

# SHASUMS256.txt names the tarball without a path, so the entry is rewritten to
# point at the copy just downloaded.
grep "  ${tarball}\$" "${tmpdir}/SHASUMS256.txt" \
    | sed "s|  ${tarball}\$|  ${tmpdir}/${tarball}|" \
    | sha256sum -c -

# The tarball records uid/gid 1000, which is the remote user in these images, so
# ownership is left to the extracting root rather than restored from the archive.
# It would otherwise be handed to that user, along with the /usr/local
# directories the archive recreates.
tar xJf "${tmpdir}/${tarball}" -C "${PREFIX}" --strip-components=1 --no-same-owner

USERNAME="${_REMOTE_USER:-root}"
if ! passwd_entry="$(getent passwd "${USERNAME}")"; then
    echo "(!) Remote user '${USERNAME}' was not found in the password database." >&2
    exit 1
fi
USER_HOME="${_REMOTE_USER_HOME:-$(printf '%s' "${passwd_entry}" | cut -d: -f6)}"
USER_GROUP="$(id -gn "${USERNAME}")"

if [ "${COREPACK}" != "none" ]; then
    if [ ! -x "${PREFIX}/bin/npm" ]; then
        echo "(!) Node.js ${node_version} ships no npm to install Corepack with; set the \"corepack\" option to \"none\"." >&2
        exit 1
    fi

    # npm's cache is only of use to this one install, so it is kept with the
    # other downloads instead of in a home directory: the default location is
    # the remote user's own cache when the remote user is root, and may hold
    # entries this feature did not put there in any case.
    "${PREFIX}/bin/npm" install -g --cache "${tmpdir}/npm-cache" \
        --no-audit --no-fund "corepack@${COREPACK}"

    # Corepack downloads package managers into COREPACK_HOME, which defaults to
    # ~/.cache/node/corepack. Creating it here keeps the first invocation from
    # writing into a root-owned cache directory. Each level is chowned, since
    # the remote user may own none of them yet.
    if [ -d "${USER_HOME}" ]; then
        corepack_cache="${USER_HOME}/.cache/node/corepack"
        mkdir -p "${corepack_cache}"
        chown "${USERNAME}:${USER_GROUP}" \
            "${USER_HOME}/.cache" "${USER_HOME}/.cache/node" "${corepack_cache}"
    else
        echo "(*) Home directory '${USER_HOME}' does not exist; skipping the Corepack cache directory." >&2
    fi
else
    # Release lines up to Node.js 24 bundle Corepack, so leaving it out means
    # removing the copy the tarball brought along.
    rm -rf "${PREFIX}/lib/node_modules/corepack" "${PREFIX}/bin/corepack"
fi

# Removed last, so Corepack can still be installed with npm above.
if [ "${KEEPNPM}" != "true" ]; then
    rm -rf "${PREFIX}/lib/node_modules/npm" "${PREFIX}/bin/npm" "${PREFIX}/bin/npx"
fi

echo "Installed Node.js $("${PREFIX}/bin/node" --version)."
if [ "${COREPACK}" != "none" ]; then
    echo "Installed Corepack $("${PREFIX}/bin/corepack" --version)."
fi
