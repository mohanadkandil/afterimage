#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/Afterimage.app dist/Afterimage-macOS.zip
printf 'Created dist/Afterimage-macOS.zip\n'
