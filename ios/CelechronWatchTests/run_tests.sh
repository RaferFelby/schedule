#!/usr/bin/env bash
set -euo pipefail

TEST_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "${TEST_DIRECTORY}/../.." && pwd)"
WATCH_TEST_BINARY="$(mktemp "${TMPDIR:-/tmp}/celechron-watch-cleanup-tests.XXXXXX")"
trap 'rm -f "${WATCH_TEST_BINARY}"' EXIT

xcrun swiftc \
  "${PROJECT_DIRECTORY}/ios/CelechronWatch/LegacyWatchCredentialCleanup.swift" \
  "${TEST_DIRECTORY}/LegacyWatchCredentialCleanupTests.swift" \
  -o "${WATCH_TEST_BINARY}"

"${WATCH_TEST_BINARY}"
