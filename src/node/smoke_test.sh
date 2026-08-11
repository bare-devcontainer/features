#!/usr/bin/env bash

set -euo pipefail

failures=0

# Runs a command and records the outcome instead of aborting, so a single run
# reports every broken check rather than only the first one.
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

check "node is on PATH" command -v node
check "node reports a version" node --version
check "node is installed under /usr/local" \
    bash -c 'test "$(command -v node)" = /usr/local/bin/node'
check "node runs a program" node -e 'console.log("Hello, world!")'
check "corepack is on PATH" command -v corepack
check "corepack reports a version" corepack --version
check "npm and npx are removed by default" \
    bash -c '! command -v npm >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1'
check "corepack is installed but not enabled" \
    bash -c '! command -v yarn >/dev/null 2>&1 && ! command -v pnpm >/dev/null 2>&1'
check "corepack cache directory is writable by the remote user" \
    bash -c 'touch "${HOME}/.cache/node/corepack/.write-test"
             rm "${HOME}/.cache/node/corepack/.write-test"'

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed."
    exit 1
fi

echo "All checks passed."
