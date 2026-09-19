#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG="$ROOT/config/cluster.env"
RUNTIME=baseline
FABRIC=switchless
BASE=http://127.0.0.1:8000
REFERENCE=""
STAGE=""
PROMOTE=0
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --runtime) RUNTIME=${2:?missing runtime}; shift 2 ;;
    --fabric) FABRIC=${2:?missing fabric}; shift 2 ;;
    --base) BASE=${2:?missing URL}; shift 2 ;;
    --reference) REFERENCE=${2:?missing reference}; shift 2 ;;
    --stage) STAGE=${2:?missing stage}; shift 2 ;;
    --promote) PROMOTE=1; shift ;;
    *) die "usage: $0 [--config FILE] --runtime baseline|b12x [--fabric switchless|switched] [--base URL] [--reference FILE] [--stage NAME] [--promote]" ;;
  esac
done
load_config "$CONFIG"
mkdir -p "$ROOT/.receipts"
[[ "$RUNTIME" == baseline || "$RUNTIME" == b12x ]] || die "invalid runtime"
[[ "$FABRIC" == switchless || "$FABRIC" == switched ]] || die "invalid fabric"

if ((PROMOTE)); then
  [[ "$RUNTIME" == b12x ]] || die "--promote is only meaningful for B12X"
  [[ "$FABRIC" == switchless ]] || die "B12X promotion requires switchless receipts"
  health="$ROOT/.receipts/gpu-health.log"
  [[ -f "$health" && $(grep -c '"tflops"' "$health") -eq 4 ]] || \
    die "four-rank burn receipt missing; run deepseek-v41-health.sh --burn"
  image_id=$(docker image inspect --format '{{.Id}}' "$B12X_IMAGE")
  fabric="$ROOT/.receipts/switchless-nccl.env"
  [[ -f "$fabric" ]] || die "switchless NCCL receipt missing; gate the B12X image first"
  fabric_status=$(sed -n 's/^STATUS=//p' "$fabric")
  fabric_ranks=$(sed -n 's/^RANKS=//p' "$fabric")
  fabric_image=$(sed -n 's/^IMAGE_ID=//p' "$fabric")
  fabric_hash=$(sed -n 's/^NCCL_LIBRARY_SHA256=//p' "$fabric")
  [[ "$fabric_status" == PASS && "$fabric_ranks" == 4 && \
     "$fabric_image" == "$image_id" && \
     "$fabric_hash" == "$SWITCHLESS_NCCL_LIBRARY_SHA256" ]] || \
    die "switchless NCCL receipt is stale or belongs to another image"
  for required in base-64k long-300k graphs-64k dspark-64k; do
    receipt="$ROOT/.receipts/b12x-$required.env"
    [[ -f "$receipt" ]] || die "missing required stage receipt: $receipt"
    stage_status=$(sed -n 's/^STATUS=//p' "$receipt")
    stage_image=$(sed -n 's/^IMAGE_ID=//p' "$receipt")
    stage_model=$(sed -n 's/^MODEL_REVISION=//p' "$receipt")
    stage_fabric=$(sed -n 's/^FABRIC=//p' "$receipt")
    [[ "$stage_status" == PASS && "$stage_image" == "$image_id" && \
       "$stage_model" == "$MODEL_REVISION" && "$stage_fabric" == switchless ]] || \
      die "stale or failed stage receipt: $receipt"
  done
  printf '%s\n' \
    'STATUS=PASS' \
    "MODEL_REVISION=$MODEL_REVISION" \
    'RANKS=4' \
    'ARCH=sm121' \
    "IMAGE_ID=$image_id" \
    'FABRIC=switchless' \
    "NCCL_LIBRARY_SHA256=$SWITCHLESS_NCCL_LIBRARY_SHA256" \
    "QUALIFIED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$ROOT/.receipts/b12x-qualified.env"
  note "promoted matching base/long/graphs/DSpark receipts for image $image_id"
  exit 0
fi

"$ROOT/tools/deepseek-v41-health.sh" --config "$CONFIG" --quick
image=$BASELINE_IMAGE; [[ "$RUNTIME" != b12x ]] || image=$B12X_IMAGE
expected=$(docker image inspect --format '{{.Id}}' "$image")
for host in "${NODES[@]}"; do
  actual=$(remote "$host" "docker image inspect --format '{{.Id}}' '$image'")
  [[ "$actual" == "$expected" ]] || die "image mismatch on $host"
done

if [[ "$RUNTIME" == b12x ]]; then
  [[ "$FABRIC" == switchless ]] || \
    die "B12X promotion receipts require the switchless fabric"
  [[ -n "$REFERENCE" ]] || die "B12X qualification requires a baseline --reference"
  case "$STAGE" in
    base-64k|long-300k|graphs-64k|dspark-64k) ;;
    *) die "B12X --stage must be base-64k, long-300k, graphs-64k, or dspark-64k" ;;
  esac
  api_receipt="$ROOT/.receipts/b12x-$STAGE-api.json"
  py_args=(--base "$BASE" --receipt "$api_receipt" --reference "$REFERENCE")
  [[ "$STAGE" != dspark-64k ]] || py_args+=(--require-dspark-metrics)
  python3 "$ROOT/tools/deepseek-v41-qualify.py" "${py_args[@]}"
  printf '%s\n' \
    'STATUS=PASS' \
    "STAGE=$STAGE" \
    "MODEL_REVISION=$MODEL_REVISION" \
    'RANKS=4' \
    'ARCH=sm121' \
    "IMAGE_ID=$expected" \
    'FABRIC=switchless' \
    "QUALIFIED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$ROOT/.receipts/b12x-$STAGE.env"
  note "stage PASS recorded. Run every stage, review logs, then use --runtime b12x --promote."
else
  [[ -z "$STAGE" ]] || die "--stage is reserved for B12X"
  receipt_suffix=""
  [[ "$FABRIC" == switchless ]] || receipt_suffix="-switched"
  python3 "$ROOT/tools/deepseek-v41-qualify.py" --base "$BASE" \
    --receipt "$ROOT/.receipts/baseline$receipt_suffix-api.json" \
    --write-reference "$ROOT/.receipts/baseline$receipt_suffix-reference.json"
  note "baseline reference: $ROOT/.receipts/baseline$receipt_suffix-reference.json"
fi
