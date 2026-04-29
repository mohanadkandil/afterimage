#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DSWIFTC="$(xcrun --find swiftc)" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
  -DCMAKE_CXX_COMPILER="$(xcrun --find clang++)" \
  -DCMAKE_OBJCXX_COMPILER="$(xcrun --find clang++)"
cmake --build build -j 4
mkdir -p build/Afterimage.app/Contents/Frameworks
cp build/libAfterimageViews.dylib build/Afterimage.app/Contents/Frameworks/libAfterimageViews.dylib
cp assets/AppIcon.icns build/Afterimage.app/Contents/Resources/AppIcon.icns
ctest --test-dir build --output-on-failure
signing_identity="${AFTERIMAGE_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')"
fi
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
  echo 'No Apple Development identity found; ad-hoc builds may require permission again after updates.'
fi
codesign --force --deep --sign "$signing_identity" build/Afterimage.app
printf '\nBuilt %s/build/Afterimage.app\n' "$PWD"
