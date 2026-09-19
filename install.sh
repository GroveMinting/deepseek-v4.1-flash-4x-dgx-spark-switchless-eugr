#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EUGR=${1:-}
CONFIG=${2:-$ROOT/config/cluster.env}
[[ -n "$EUGR" ]] || { echo "usage: $0 /path/to/spark-vllm-docker [config/cluster.env]" >&2; exit 2; }
EUGR=$(cd "$EUGR" && pwd)
[[ -f "$EUGR/run-recipe.sh" ]] || { echo "not an eugr checkout: $EUGR" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "missing config: $CONFIG" >&2; exit 1; }

rendered=$(mktemp -d)
trap 'rm -rf "$rendered"' EXIT
python3 "$ROOT/tools/render-recipes.py" --config "$CONFIG" --out "$rendered"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$EUGR/.local-backups/deepseek-v41-switchless-4x-$stamp"
manifest="$EUGR/.deepseek-v41-switchless-4x-installed"
[[ ! -e "$manifest" ]] || { echo "already installed; run uninstall.sh first" >&2; exit 1; }
mkdir -p "$backup"

install_one() {
  local src=$1 rel=$2 dst="$EUGR/$2" state=new
  mkdir -p "$backup/$(dirname "$rel")" "$(dirname "$dst")"
  if [[ -e "$dst" ]]; then
    mv "$dst" "$backup/$rel"
    state=replaced
  fi
  cp -a "$src" "$dst"
  printf '%s|%s\n' "$state" "$rel" >> "$manifest.tmp"
}

for src in "$rendered"/*.yaml; do install_one "$src" "recipes/$(basename "$src")"; done
install_one "$ROOT/mods/deepseek-v41-runtime-check" "mods/deepseek-v41-runtime-check"
install_one "$ROOT/mods/deepseek-v41-b12x-candidate-check" "mods/deepseek-v41-b12x-candidate-check"
for name in deepseek-v41-smoke.sh deepseek-v41-inspect.sh deepseek-v41-health.sh deepseek-v41-qualify.py; do
  install_one "$ROOT/tools/$name" "tools/$name"
done
printf 'backup=%s\n' "$backup" > "$manifest"
cat "$manifest.tmp" >> "$manifest"
rm -f "$manifest.tmp"
echo "installed 16 recipes and check tools into $EUGR"
echo "reversible backup: $backup"
