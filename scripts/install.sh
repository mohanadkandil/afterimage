#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x build/Litt.app/Contents/MacOS/Litt ]] || { echo 'Run ./scripts/build.sh first' >&2; exit 1; }
install_dir="$HOME/Applications"
mkdir -p "$install_dir" "$HOME/.local/bin"
if pgrep -f "$install_dir/Litt.app/Contents/MacOS/Litt" >/dev/null; then
  echo 'Quit Litt before installing an update.' >&2
  exit 1
fi
ditto build/Litt.app "$install_dir/Litt.app"
cat > "$HOME/.local/bin/litt" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
app="$HOME/Applications/Litt.app"
if [[ $# -eq 0 ]]; then open "$app"; else exec "$app/Contents/MacOS/Litt" "$@"; fi
LAUNCHER
chmod +x "$HOME/.local/bin/litt"
printf 'Installed %s/Litt.app\nCLI: %s/.local/bin/litt\n' "$install_dir" "$HOME"
