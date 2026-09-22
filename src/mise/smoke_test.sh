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
check "MISE_DATA_DIR points at the mounted volume" \
    bash -c 'test "${MISE_DATA_DIR:-}" = /var/lib/mise'
check "MISE_CACHE_DIR points at the mounted volume" \
    bash -c 'test "${MISE_CACHE_DIR:-}" = /var/cache/mise'
check "the shims directory is on PATH" \
    bash -c 'tr ":" "\n" <<< "${PATH}" | grep -qx /var/lib/mise/shims'
check "remote user belongs to the mise group" \
    bash -c 'id -nG | tr " " "\n" | grep -qx mise'
check "data and cache directories are group-writable and setgid" \
    bash -c 'test "$(stat -c "%A %G" /var/lib/mise)" = "drwxrwsr-x mise"
             test "$(stat -c "%A %G" /var/cache/mise)" = "drwxrwsr-x mise"'
check "data and cache directories are writable by the remote user" \
    bash -c 'touch /var/lib/mise/.write-test /var/cache/mise/.write-test
             rm /var/lib/mise/.write-test /var/cache/mise/.write-test'
check "files created there are owned by the remote user" \
    bash -c 'touch /var/lib/mise/.owner-test
             owner="$(stat -c %u /var/lib/mise/.owner-test)"
             rm /var/lib/mise/.owner-test
             test "${owner}" = "$(id -u)"'
# Node.js, whose backend takes the version list and the tarball from nodejs.org.
# A backend that reaches the GitHub API cannot be used here: its unauthenticated
# rate limit is per IP, and GitHub-hosted runners share one.
check "mise installs and runs a tool" \
    mise exec node@24 -- node -e 'console.log("Hello, world!")'
check "the tool was installed into the data directory" \
    bash -c 'test -d /var/lib/mise/installs/node'
check "the tool's shim was written to the shims directory" \
    bash -c 'test -x /var/lib/mise/shims/node'

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed."
    exit 1
fi

echo "All checks passed."
