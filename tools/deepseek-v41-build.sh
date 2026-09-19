#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
mkdir -p "$ROOT/.receipts"
RUNTIME=baseline
SOURCE_IMAGE=${B12X_SOURCE_IMAGE:-}
FORCE=0
while (($#)); do
  case "$1" in
    --runtime) RUNTIME=${2:?missing runtime}; shift 2 ;;
    --source-image) SOURCE_IMAGE=${2:?missing image}; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) die "usage: $0 --runtime baseline|b12x [--source-image IMAGE] [--force]" ;;
  esac
done
case "$RUNTIME" in
  baseline)
    args=(); ((FORCE == 0)) || args+=(--force)
    exec "$ROOT/runtime/build-v41-image.sh" "${args[@]}"
    ;;
  b12x)
    [[ ${DSV41_ALLOW_UNQUALIFIED_B12X:-NO} == YES ]] || \
      die "set DSV41_ALLOW_UNQUALIFIED_B12X=YES for candidate construction"
    [[ -n "$SOURCE_IMAGE" ]] || die "provide --source-image from eugr's B12X source build; see docs/B12X-READINESS.md"
    docker image inspect "$SOURCE_IMAGE" >/dev/null || die "source image not found: $SOURCE_IMAGE"
    mkdir -p "$ROOT/build/b12x-context/nccl"
    bash "$ROOT/switchless/install-switchless-nccl.sh" --dest "$ROOT/build/b12x-context/nccl"
    cp "$ROOT/runtime/Dockerfile.b12x" "$ROOT/build/b12x-context/Dockerfile"
    source_id=$(docker image inspect --format '{{.Id}}' "$SOURCE_IMAGE")
    docker build --pull=false -f "$ROOT/build/b12x-context/Dockerfile" \
      --build-arg BASE_IMAGE="$SOURCE_IMAGE" \
      --build-arg MODEL_REVISION="$MODEL_REVISION" \
      --build-arg SOURCE_IMAGE_ID="$source_id" \
      -t "$B12X_IMAGE" "$ROOT/build/b12x-context"
    docker image inspect --format '{{.Id}}' "$B12X_IMAGE" > "$ROOT/.receipts/b12x-candidate-image-id"
    ;;
  *) die "runtime must be baseline or b12x" ;;
esac
