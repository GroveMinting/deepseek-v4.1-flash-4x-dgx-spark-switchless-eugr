#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EUGR=${1:-}
[[ -n "$EUGR" ]] || { echo "usage: $0 /path/to/spark-vllm-docker" >&2; exit 2; }
EUGR=$(cd "$EUGR" && pwd)
manifest="$EUGR/.deepseek-v41-switchless-4x-installed"
[[ -f "$manifest" ]] || { echo "install receipt not found: $manifest" >&2; exit 1; }
backup=$(sed -n 's/^backup=//p' "$manifest")
[[ -n "$backup" && -d "$backup" ]] || { echo "backup missing: $backup" >&2; exit 1; }
while IFS='|' read -r state rel; do
  [[ "$state" == new || "$state" == replaced ]] || continue
  dst="$EUGR/$rel"
  if [[ -e "$dst" ]]; then
    moved="$backup/.removed-by-uninstall/$rel"
    mkdir -p "$(dirname "$moved")"
    mv "$dst" "$moved"
  fi
  if [[ "$state" == replaced ]]; then
    mkdir -p "$(dirname "$dst")"
    mv "$backup/$rel" "$dst"
  fi
done < <(tail -n +2 "$manifest")
mv "$manifest" "$backup/install-receipt"
echo "uninstalled extension; replaced files restored"
echo "removed extension files remain recoverable under $backup/.removed-by-uninstall"
