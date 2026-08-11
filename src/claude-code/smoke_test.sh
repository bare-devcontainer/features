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

check "claude is on PATH" command -v claude
check "claude reports a version" claude --version
check "CLAUDE_CONFIG_DIR points at the mounted volume" \
    bash -c 'test "${CLAUDE_CONFIG_DIR:-}" = /var/lib/claude-code'
check "remote user belongs to the config group" \
    bash -c 'id -nG | tr " " "\n" | grep -qx claude-code'
check "config directory is group-writable and setgid" \
    bash -c 'test "$(stat -c "%A %G" /var/lib/claude-code)" = "drwxrwsr-x claude-code"'
check "config directory is writable by the remote user" \
    bash -c 'touch /var/lib/claude-code/.write-test && rm /var/lib/claude-code/.write-test'
check "files created there are owned by the remote user" \
    bash -c 'touch /var/lib/claude-code/.owner-test
             owner="$(stat -c %u /var/lib/claude-code/.owner-test)"
             rm /var/lib/claude-code/.owner-test
             test "${owner}" = "$(id -u)"'
check "apt source is kept by default" test -f /etc/apt/sources.list.d/claude-code.list
check "signing key is kept by default" test -f /usr/share/keyrings/claude-code.asc

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed."
    exit 1
fi

echo "All checks passed."
