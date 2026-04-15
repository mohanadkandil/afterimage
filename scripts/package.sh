#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/Litt.app dist/Litt-macOS.zip
printf 'Created dist/Litt-macOS.zip\n'
