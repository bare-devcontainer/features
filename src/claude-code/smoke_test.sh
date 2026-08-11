#!/usr/bin/env bash
#
# Smoke test for the claude-code feature.
#
# Runs inside a started Dev Container that has this feature installed with its
# default options, as the container's remote user. See
# .github/workflows/smoke-test.yml for how it is invoked.

set -euo pipefail

failures=0

# Runs a command and records the outcome instead of aborting, so a single run
# reports every broken check rather than only the first one.
check() {
    local label="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        echo "ok   - ${label}"
    else
        echo "FAIL - ${label}"
        failures=$((failures + 1))
    fi
}

check "claude is on PATH" command -v claude
check "claude reports a version" claude --version
check "config directory links to the mounted volume" \
    bash -c 'test "$(readlink "${HOME}/.claude")" = /var/lib/claude-code'
check "config directory is writable by the remote user" \
    bash -c 'touch "${HOME}/.claude/.write-test" && rm "${HOME}/.claude/.write-test"'
check "apt source is kept by default" test -f /etc/apt/sources.list.d/claude-code.list
check "signing key is kept by default" test -f /usr/share/keyrings/claude-code.asc

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed."
    exit 1
fi

echo "All checks passed."
