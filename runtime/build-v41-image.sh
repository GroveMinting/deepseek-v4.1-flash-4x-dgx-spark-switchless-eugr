#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "$ROOT/runtime/common.sh"
load_versions

FORCE=0
while (($#)); do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) echo "usage: $0 [--force]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if docker image inspect "$BASELINE_IMAGE" >/dev/null 2>&1 && ((FORCE == 0)); then
  note "$BASELINE_IMAGE already exists; use --force to rebuild"
  exit 0
fi

bash "$ROOT/runtime/prepare-upstreams.sh"
bash "$ROOT/switchless/install-switchless-nccl.sh" --dest "$ROOT/build/runtime-context/nccl"
VENDOR="$ROOT/vendor/tony-v41"

if ! docker image inspect vllm-dsv41:overlay5 >/dev/null 2>&1; then
  if ! docker image inspect vllm-dsv41:overlay1 >/dev/null 2>&1; then
    if [[ -x "$VENDOR/build/build_overlay1.sh" || -f "$VENDOR/build/build_overlay1.sh" ]]; then
      (cd "$VENDOR" && bash build/build_overlay1.sh)
    else
      die "Tony's overlay1 prerequisite is absent. Build vllm-dsv41:overlay1 from vendor/tony-v41/build/Dockerfile.overlay at locked vLLM $VLLM_COMMIT, then rerun. The helper will not guess a changed upstream command."
    fi
  fi
  for stage in 3 4 5; do
    script="$VENDOR/build/build_overlay${stage}.sh"
    [[ -f "$script" ]] || die "missing Tony overlay script: $script"
    (cd "$VENDOR" && MAX_JOBS=2 FLASHINFER_NVCC_THREADS=1 bash "$script")
  done
fi

docker image inspect vllm-dsv41:overlay5 >/dev/null || die "Tony overlay5 was not produced"
# shellcheck source=/dev/null
source "$ROOT/.resolved-refs"
docker build --pull=false \
  -f "$ROOT/runtime/Dockerfile.runtime" \
  --build-arg BASE_IMAGE=vllm-dsv41:overlay5 \
  --build-arg RUNTIME_LANE=baseline \
  --build-arg MODEL_REVISION="$MODEL_REVISION" \
  --build-arg VLLM_COMMIT="$VLLM_COMMIT" \
  --build-arg UPSTREAM_COMMIT="$TONY_COMMIT" \
  -t "$BASELINE_IMAGE" "$ROOT/build/runtime-context"
docker run --rm "$BASELINE_IMAGE" bash -lc \
  'source /opt/dsv41/runtime.env; test "$RUNTIME_LANE" = baseline; test -s /opt/dsv41/PATCHES.sha256'
docker image inspect --format '{{.Id}}' "$BASELINE_IMAGE" > "$ROOT/.receipts/baseline-image-id"
note "built immutable runtime $BASELINE_IMAGE"
