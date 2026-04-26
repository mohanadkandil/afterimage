#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 4
mkdir -p build/Litt.app/Contents/Frameworks
cp build/libLittViews.dylib build/Litt.app/Contents/Frameworks/libLittViews.dylib
cp assets/AppIcon.icns build/Litt.app/Contents/Resources/AppIcon.icns
ctest --test-dir build --output-on-failure
signing_identity="${LITT_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')"
fi
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
  echo 'No Apple Development identity found; ad-hoc builds may require permission again after updates.'
fi
codesign --force --deep --sign "$signing_identity" build/Litt.app
printf '\nBuilt %s/build/Litt.app\n' "$PWD"
