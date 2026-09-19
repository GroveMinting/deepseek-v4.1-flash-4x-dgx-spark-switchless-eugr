#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG="$ROOT/config/cluster.env"
MODE=burn
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --quick) MODE=quick; shift ;;
    --burn) MODE=burn; shift ;;
    *) die "usage: $0 [--config FILE] [--quick|--burn]" ;;
  esac
done
load_config "$CONFIG"
for host in "${NODES[@]}"; do
  remote "$host" "set -eu
    test \"\$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)\" = 1
    cap=\$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
    test \"\$cap\" = 12.1
    pids=\$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null || true)
    test -z \"\$pids\" || { echo 'GPU compute process already active' >&2; exit 1; }
    nvidia-smi --query-gpu=name,compute_cap,clocks.max.sm,power.limit --format=csv,noheader"
done
[[ "$MODE" == burn ]] || { note "quick GPU identity/idle gate passed on four SM121 ranks"; exit 0; }

image=${BASELINE_IMAGE}
docker image inspect "$image" >/dev/null || die "build $image before the burn gate"
mkdir -p "$ROOT/.receipts"
receipt="$ROOT/.receipts/gpu-health.log"
: > "$receipt"
scp_opts=(-P "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12)
[[ -z ${SSH_KEY:-} ]] || scp_opts+=(-i "$SSH_KEY")
for host in "${NODES[@]}"; do
  scp "${scp_opts[@]}" "$ROOT/tools/gpu_burn.py" "$SSH_USER@$host:/tmp/dsv41-gpu-burn.py"
  note "$host: running 15-second FP16 health gate (minimum 50 TFLOPS)"
  result=$(remote "$host" docker run --rm --gpus all -v /tmp/dsv41-gpu-burn.py:/burn.py:ro "$image" python /burn.py)
  printf '%s %s\n' "$host" "$result" | tee -a "$receipt"
done
note "GPU burn gate passed on all four ranks"
note "health receipt: $receipt"
