#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 4
cp assets/AppIcon.icns build/Litt.app/Contents/Resources/AppIcon.icns
ctest --test-dir build --output-on-failure
codesign --force --deep --sign - build/Litt.app
printf '\nBuilt %s/build/Litt.app\n' "$PWD"
