#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG="$ROOT/config/cluster.env"
[[ ${1:-} != --config ]] || { CONFIG=${2:?missing config}; shift 2; }
(($# == 0)) || die "usage: $0 [--config FILE]"
load_config "$CONFIG"
require_switchless_config
IMAGE=${IMAGE:-$BASELINE_IMAGE}
PY="$ROOT/switchless/nccl_smoke.py"
docker image inspect "$IMAGE" >/dev/null || die "custom image missing: $IMAGE"
expected_image_id=$(docker image inspect --format '{{.Id}}' "$IMAGE")
for host in "${NODES[@]}"; do
  actual_image_id=$(remote "$host" "docker image inspect --format '{{.Id}}' '$IMAGE'")
  [[ "$actual_image_id" == "$expected_image_id" ]] || \
    die "image mismatch on $host: $actual_image_id"
done

scp_opts=(-P "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12)
[[ -z ${SSH_KEY:-} ]] || scp_opts+=(-i "$SSH_KEY")
for host in "${NODES[@]}"; do
  remote "$host" "mkdir -p /tmp/dsv41-switchless-gate"
  scp "${scp_opts[@]}" "$PY" "$SSH_USER@$host:/tmp/dsv41-switchless-gate/"
done

run_rank() {
  local rank=$1 host=${NODES[$1]}
  remote "$host" "docker run --rm --network host --ipc host --shm-size 32g --gpus all \
    --device /dev/infiniband --cap-add IPC_LOCK --ulimit memlock=-1:-1 \
    -v /tmp/dsv41-switchless-gate:/gate:ro \
    -e LD_PRELOAD=/opt/nccl-switchless/libnccl.so.2 \
    -e VLLM_NCCL_SO_PATH=/opt/nccl-switchless/libnccl.so.2 \
    -e NCCL_SWITCHLESS_RING_ONLY=1 -e NCCL_SKIP_TREE_CONNECT=1 \
    -e NCCL_SOCKET_IFNAME=$MGMT_IF -e GLOO_SOCKET_IFNAME=$MGMT_IF \
    -e NCCL_NET=IB -e NCCL_IB_DISABLE=0 -e NCCL_IB_HCA=$F0_HCA,$F1_HCA \
    -e NCCL_IB_GID_INDEX=$GID_INDEX -e NCCL_IB_SUBNET_PREFIX_LEN=24 \
    -e NCCL_IB_SUBNET_AWARE_ROUTING=1 -e NCCL_ALGO=Ring \
    -e NCCL_PROTO=LL,LL128,Simple -e NCCL_P2P_LEVEL=SYS \
    -e NCCL_MIN_NCHANNELS=4 -e NCCL_MAX_NCHANNELS=4 -e NCCL_CROSS_NIC=1 \
    -e NCCL_CUMEM_ENABLE=0 -e NCCL_IGNORE_CPU_AFFINITY=1 \
    $IMAGE python -m torch.distributed.run --nnodes=4 --nproc-per-node=1 \
      --node-rank=$rank --master-addr=${NODES[0]} --master-port=29579 /gate/nccl_smoke.py"
}

"$ROOT/switchless/fabric-verify.sh" --config "$CONFIG"
pids=()
for rank in 3 2 1; do run_rank "$rank" & pids+=("$!"); done
status=0
run_rank 0 || status=$?
for pid in "${pids[@]}"; do wait "$pid" || status=$?; done
((status == 0)) || die "NCCL collective gate failed"
mkdir -p "$ROOT/.receipts"
printf '%s\n' \
  'STATUS=PASS' \
  'RANKS=4' \
  "IMAGE_ID=$expected_image_id" \
  "NCCL_VERSION=$SWITCHLESS_NCCL_VERSION" \
  "NCCL_LIBRARY_SHA256=$SWITCHLESS_NCCL_LIBRARY_SHA256" \
  "GATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$ROOT/.receipts/switchless-nccl.env"
note "NCCL TP4 collective gate passed on the patched switchless ring"
note "fabric receipt: $ROOT/.receipts/switchless-nccl.env"
