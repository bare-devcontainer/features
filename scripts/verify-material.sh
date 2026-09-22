#!/usr/bin/env bash
#
# verify-material.sh — check that the release checksums a feature's install
# script verifies downloads against are the ones upstream signed. Reads the
# working tree only: it downloads nothing, writes nothing and needs no network,
# so what it proves holds for whatever the repository currently has committed.
# Exits non-zero on the first file that does not verify.
#
# The features it covers, and the signature and key for each, are listed in
# signed-material.json next to this script; pin-checksums.sh writes the files
# this reads.
#
# Requires: minisign, jq
#
# Usage:
#   verify-material.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATERIAL="${SCRIPT_DIR}/signed-material.json"

count=0
while IFS=$'\t' read -r feature checksums signature key; do
  echo "${feature}: verifying ${checksums} against ${signature} with ${key}" >&2
  minisign -V -m "$checksums" -x "$signature" -p "$key"
  count=$((count + 1))
done < <(jq -r '.[] | [.feature, .checksums, .signature, .key] | @tsv' "$MATERIAL")

# An empty table would otherwise report success without having checked anything.
if [ "$count" -eq 0 ]; then
  echo "(!) ${MATERIAL} lists no material to verify." >&2
  exit 1
fi

echo "Verified vendored checksums for ${count} feature(s)." >&2
