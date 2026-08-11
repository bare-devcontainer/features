#!/usr/bin/env bash
#
# update-material.sh — refresh the trust material vendored in this repository,
# writing changed files in place in the working tree. Prints "true" or "false"
# to stdout depending on whether anything changed; per-file download and
# comparison progress goes to stderr. Performs no git or GitHub operations.
#
# Usage:
#   update-material.sh
set -euo pipefail

# path: the file tracked in this repository, url: where upstream publishes it.
MATERIALS='[
  {
    "path": "src/claude-code/claude-code.asc",
    "url": "https://downloads.claude.ai/keys/claude-code.asc"
  }
]'

changed=false
while IFS=$'\t' read -r path url; do
  echo "Downloading ${url} -> ${path}" >&2

  # Downloaded to a temporary file first so a failed request cannot leave a
  # truncated key behind in the working tree.
  tmp=$(mktemp)
  wget -q -T 30 -t 3 -O "$tmp" "$url"

  if cmp -s "$tmp" "$path"; then
    echo "  unchanged" >&2
  else
    echo "  changed" >&2
    changed=true
  fi

  chmod 644 "$tmp"
  mv "$tmp" "$path"
done < <(jq -r '.[] | [.path, .url] | @tsv' <<< "$MATERIALS")

echo "$changed"
