#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${IMOBILEDEVICE_SOURCE:?Set to libimobiledevice 1.4.0 source directory}"
: "${PLIST_SOURCE:?Set to libplist 2.7.0 source directory}"
build_root=$(mktemp -d "${TMPDIR:-/tmp}/airbattery-watch-build.XXXXXX")
trap 'rm -rf "$build_root"' EXIT
clang -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -Wall -Wextra -Werror \
    -I "$IMOBILEDEVICE_SOURCE/include" -I "$PLIST_SOURCE/include" \
    AirBattery/libimobiledevice/bin/comptest.c \
    AirBattery/libimobiledevice/lib/libimobiledevice-1.0.6.dylib \
    AirBattery/libimobiledevice/lib/libplist-2.0.12.dylib -o "$build_root/comptest"
cp "$build_root/comptest" AirBattery/libimobiledevice/bin/comptest
