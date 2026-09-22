#!/usr/bin/env bash
#
# pin-checksums.sh — re-pin a feature's vendored release checksums to a named
# upstream release. Downloads the checksum file and the signature upstream
# published for it, and writes both into the working tree only once the
# signature verifies against the vendored public key. Performs no git
# operations.
#
# Which file belongs to which feature is listed in signed-material.json next to
# this script. The checksums decide which release the feature installs, so
# moving them also needs a version bump in its devcontainer-feature.json.
#
# Requires: minisign, jq, wget
#
# Usage:
#   pin-checksums.sh <feature> <tag>
#
# Example:
#   pin-checksums.sh mise v2026.9.11
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATERIAL="${SCRIPT_DIR}/signed-material.json"

if [ "$#" -ne 2 ]; then
  sed -n '/^# Usage:/,/^# *pin-checksums.sh <feature> <tag>/p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
feature="$1"
tag="$2"

entry="$(jq -e --arg feature "$feature" '.[] | select(.feature == $feature)' "$MATERIAL")" || {
  echo "(!) ${MATERIAL} has no entry for '${feature}'. Known: $(jq -r '[.[].feature] | join(", ")' "$MATERIAL")" >&2
  exit 1
}

repository="$(jq -r '.repository' <<< "$entry")"
checksums="$(jq -r '.checksums' <<< "$entry")"
signature="$(jq -r '.signature' <<< "$entry")"
key="$(jq -r '.key' <<< "$entry")"
releases="https://github.com/${repository}/releases/download/${tag}"

tmp_checksums=$(mktemp)
tmp_signature=$(mktemp)
trap 'rm -f "$tmp_checksums" "$tmp_signature"' EXIT

echo "Downloading ${repository} ${tag} checksums" >&2
wget -q -T 30 -t 3 -O "$tmp_checksums" "${releases}/$(basename "$checksums")"
wget -q -T 30 -t 3 -O "$tmp_signature" "${releases}/$(basename "$signature")"

echo "Verifying the signature against ${key}" >&2
minisign -V -m "$tmp_checksums" -x "$tmp_signature" -p "$key"

if cmp -s "$tmp_checksums" "$checksums" && cmp -s "$tmp_signature" "$signature"; then
  echo "${checksums} already pins ${tag}; nothing to do." >&2
  exit 0
fi

chmod 644 "$tmp_checksums" "$tmp_signature"
# Moved out of the trap's reach, since the files are now the working tree's.
mv "$tmp_checksums" "$checksums"
mv "$tmp_signature" "$signature"
trap - EXIT

echo "Pinned ${checksums} to ${tag}. Bump the feature version to publish it." >&2
