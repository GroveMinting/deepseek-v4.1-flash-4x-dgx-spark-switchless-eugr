#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG="$ROOT/config/cluster.env"
VERIFY_ONLY=0
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    *) die "usage: $0 [--config FILE] [--verify-only]" ;;
  esac
done
load_config "$CONFIG"
EUGR_DIR=$(cd "$EUGR_DIR" && pwd)
helper="$EUGR_DIR/hf-download.sh"

if ((VERIFY_ONLY == 0)); then
  [[ -x "$helper" || -f "$helper" ]] || die "eugr hf-download.sh not found: $helper"
  grep -q -- '--revision' "$helper" || die "this eugr hf-download.sh cannot pin a revision"
  note "downloading $MODEL_ID at immutable revision $MODEL_REVISION"
  (cd "$EUGR_DIR" && bash "$helper" "$MODEL_ID" --revision "$MODEL_REVISION" -c --copy-parallel)
fi

repo_dir="models--${MODEL_ID//\//--}"
for host in "${NODES[@]}"; do
  result=$(remote "$host" "set -eu
    snapshot='$MODEL_CACHE/hub/$repo_dir/snapshots/$MODEL_REVISION'
    test -d \"\$snapshot\"
    test -f \"\$snapshot/model.safetensors.index.json\"
    count=\$(find -L \"\$snapshot\" -maxdepth 1 -type f -name 'model-*-of-*.safetensors' | wc -l)
    test \"\$count\" -eq '$MODEL_EXPECTED_SHARDS'
    printf '%s %s\\n' \"\$count\" \"\$snapshot\"")
  note "$host: verified $result"
done
note "official checkpoint verified on four ranks: revision $MODEL_REVISION, $MODEL_EXPECTED_SHARDS shards"
