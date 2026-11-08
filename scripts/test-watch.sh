#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/airbattery-watch-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
export WATCH_TEST_ROOT="$test_root"
swiftc -swift-version 5 AirBattery/BatteryInfo/IDeviceBattery.swift AirBattery/BatteryInfo/AirBatteryModel.swift tests/watch/Stubs.swift tests/watch/main.swift -o "$test_root/tests"
"$test_root/tests" "$@"
if [[ -n "${IMOBILEDEVICE_SOURCE:-}" && -n "${PLIST_SOURCE:-}" ]]; then
    mkdir -p "$test_root/bin"
    ln -s "$PWD/AirBattery/libimobiledevice/lib" "$test_root/lib"
    clang -fsanitize=address -g -Wall -Wextra -Werror \
        -I "$IMOBILEDEVICE_SOURCE/include" -I "$PLIST_SOURCE/include" \
        AirBattery/libimobiledevice/bin/comptest.c tests/watch/MockCompanion.c \
        AirBattery/libimobiledevice/lib/libplist-2.0.12.dylib -o "$test_root/bin/helper"
    python3 tests/watch/helper.py "$test_root/bin/helper"
fi
