#!/usr/bin/env bash
#
# Scenario test: with keepAptSource disabled, the CLI is still installed but the
# APT source and signing key are gone from the image.

set -e

source dev-container-features-test-lib

check "claude is on PATH" bash -c "command -v claude"
check "apt source is removed" bash -c "! test -e /etc/apt/sources.list.d/claude-code.list"
check "signing key is removed" bash -c "! test -e /usr/share/keyrings/claude-code.asc"

reportResults
