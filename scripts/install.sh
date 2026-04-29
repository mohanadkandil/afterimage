#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x build/Afterimage.app/Contents/MacOS/Afterimage ]] || { echo 'Run ./scripts/build.sh first' >&2; exit 1; }
install_dir="$HOME/Applications"
mkdir -p "$install_dir" "$HOME/.local/bin"
if pgrep -f "$install_dir/Afterimage.app/Contents/MacOS/Afterimage" >/dev/null; then
  echo 'Quit Afterimage before installing an update.' >&2
  exit 1
fi
ditto build/Afterimage.app "$install_dir/Afterimage.app"
cat > "$HOME/.local/bin/afterimage" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
app="$HOME/Applications/Afterimage.app"
if [[ $# -eq 0 ]]; then open "$app"; else exec "$app/Contents/MacOS/Afterimage" "$@"; fi
LAUNCHER
chmod +x "$HOME/.local/bin/afterimage"
printf 'Installed %s/Afterimage.app\nCLI: %s/.local/bin/afterimage\n' "$install_dir" "$HOME"
