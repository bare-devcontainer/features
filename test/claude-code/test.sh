#!/usr/bin/env bash
#
# Default test for the claude-code feature: the CLI is on PATH and the remote
# user owns its configuration directory.

set -e

source dev-container-features-test-lib

check "claude is on PATH" bash -c "command -v claude"
check "claude reports a version" bash -c "claude --version"
check "config directory links to the mounted volume" bash -c "test \"\$(readlink \"${HOME}/.claude\")\" = /var/lib/claude-code"
check "config directory is writable by the remote user" bash -c "touch \"${HOME}/.claude/.write-test\" && rm \"${HOME}/.claude/.write-test\""
check "apt source is present" bash -c "test -f /etc/apt/sources.list.d/claude-code.list"

reportResults
