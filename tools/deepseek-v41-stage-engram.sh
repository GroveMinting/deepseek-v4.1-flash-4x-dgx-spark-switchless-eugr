#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG="$ROOT/config/cluster.env"
RANGES="$ROOT/config/engram-ranges"
PLAN=0
MBPS=600
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --ranges) RANGES=${2:?missing ranges}; shift 2 ;;
    --mbps) MBPS=${2:?missing rate}; shift 2 ;;
    --plan) PLAN=1; shift ;;
    *) die "usage: $0 [--config FILE] [--ranges FILE] [--mbps N] [--plan]" ;;
  esac
done
load_config "$CONFIG"
MODEL_DIR=${MODEL_DIR:-}
[[ -n "$MODEL_DIR" ]] || die "set MODEL_DIR to the resolved official snapshot path"
[[ "$MODEL_DIR" =~ ^/[A-Za-z0-9_./:@+-]+$ ]] || die "unsafe MODEL_DIR"
[[ "$MBPS" =~ ^[0-9]+$ ]] || die "invalid --mbps"

if ((PLAN)); then
  note "Each rank needs about 48 GB local NVMe for sparse Engram rows."
  note "1. Boot the baseline base profile once and capture each rank's two Engram row ranges."
  note "2. Copy config/engram-ranges.example to config/engram-ranges and replace every placeholder."
  note "3. Re-run: $0 --config $CONFIG --ranges config/engram-ranges"
  note "Source: $MODEL_DIR"
  note "Destination: $ENGRAM_LOCAL_ROOT"
  exit 0
fi

[[ -f "$RANGES" ]] || die "ranges file not found: $RANGES"
grep -q REPLACE_WITH "$RANGES" && die "ranges file still contains placeholders"
tool="$ROOT/build/runtime-context/engram_local.py"
[[ -f "$tool" ]] || die "run runtime/prepare-upstreams.sh first"
scp_opts=(-P "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12)
[[ -z ${SSH_KEY:-} ]] || scp_opts+=(-i "$SSH_KEY")
for rank in 0 1 2 3; do
  line=$(awk -v r="$rank" '$1 == r {print; found=1} END {if (!found) exit 1}' "$RANGES") || die "rank $rank missing from ranges"
  read -r -a fields <<< "$line"
  ((${#fields[@]} >= 3)) || die "rank $rank needs both Engram layer ranges"
  for range in "${fields[@]:1}"; do
    [[ "$range" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]] || die "unsafe range for rank $rank: $range"
  done
  host=${NODES[$rank]}
  remote "$host" "mkdir -p /tmp/dsv41-engram-stage"
  scp "${scp_opts[@]}" "$tool" "$SSH_USER@$host:/tmp/dsv41-engram-stage/engram_local.py"
  args=("${fields[@]:1}")
  remote "$host" python3 /tmp/dsv41-engram-stage/engram_local.py \
    "$MODEL_DIR" "$ENGRAM_LOCAL_ROOT" "${args[@]}" "--mbps=$MBPS"
done
note "node-local Engram staging and byte-sample verification passed on four ranks"
