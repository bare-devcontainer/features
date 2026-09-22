#!/usr/bin/env bash

set -euo pipefail

failures=0

check() {
    local label="$1"
    shift

    local output
    local status=0
    # The `||` keeps the assignment out of `set -e`'s reach, which would
    # otherwise abort the whole run on the first failing check.
    output="$("$@" 2>&1)" || status=$?

    if [ "${status}" -eq 0 ]; then
        echo "ok   - ${label}"
    else
        echo "FAIL - ${label} (exit ${status})"
        if [ -n "${output}" ]; then
            echo "${output}" | sed 's/^/       /'
        fi
        failures=$((failures + 1))
    fi
}

check "mise is on PATH" command -v mise
check "mise reports a version" mise --version
check "mise is installed under /usr/local" \
    bash -c 'test "$(command -v mise)" = /usr/local/bin/mise'
check "the installed binary is owned by root" \
    bash -c 'test "$(stat -c %u /usr/local/bin/mise)" = 0'
check "the shims directory is on PATH" \
    bash -c 'tr ":" "\n" <<< "${PATH}" | grep -qx /usr/local/share/mise/shims'
check "the shims path resolves into the remote user's home" \
    bash -c 'test "$(readlink -f /usr/local/share/mise)" = "${HOME}/.local/share/mise"'
check "the data and cache directories are owned by the remote user" \
    bash -c 'test "$(stat -c %u "${HOME}/.local/share/mise")" = "$(id -u)"
             test "$(stat -c %u "${HOME}/.cache/mise")" = "$(id -u)"'
check "the directories above them are owned by the remote user" \
    bash -c 'for d in "${HOME}/.local" "${HOME}/.local/share" "${HOME}/.cache"; do
                 test "$(stat -c %u "${d}")" = "$(id -u)" || exit 1
             done'
check "the data directory is writable by the remote user" \
    bash -c 'touch "${HOME}/.local/share/mise/.write-test"
             rm "${HOME}/.local/share/mise/.write-test"'
# Node.js, whose backend takes the version list and the tarball from nodejs.org.
# A backend that reaches the GitHub API cannot be used here: its unauthenticated
# rate limit is per IP, and GitHub-hosted runners share one.
check "mise installs and runs a tool" \
    mise exec node@24 -- node -e 'console.log("Hello, world!")'
check "the tool was installed into the data directory" \
    bash -c 'test -d "${HOME}/.local/share/mise/installs/node"'
check "the tool's shim was written to the shims directory" \
    bash -c 'test -x /usr/local/share/mise/shims/node'

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed."
    exit 1
fi

echo "All checks passed."
