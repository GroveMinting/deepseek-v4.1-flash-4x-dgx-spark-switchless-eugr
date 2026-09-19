#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE=${1:-http://127.0.0.1:8000}
exec python3 "$ROOT/tools/deepseek-v41-qualify.py" --base "$BASE"
