#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/svitlobot-battery-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library \
    -module-cache-path "$test_dir/module-cache" \
    "$repo_dir/SvitloBot/api/LowBatteryAlertMonitor.swift" \
    "$repo_dir/tests/LowBatteryAlertMonitorTests.swift" \
    -o "$test_dir/low-battery-tests"
"$test_dir/low-battery-tests"
