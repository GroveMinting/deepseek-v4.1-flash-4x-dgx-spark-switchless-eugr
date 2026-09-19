#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:-$ROOT/config/cluster.env}
OUT=${2:-$ROOT/rendered-recipes}
exec python3 "$ROOT/tools/render-recipes.py" --config "$CONFIG" --out "$OUT"
