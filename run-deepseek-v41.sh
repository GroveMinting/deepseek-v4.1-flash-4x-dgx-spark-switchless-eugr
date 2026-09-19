#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions

CONFIG="$ROOT/config/cluster.env"
RUNTIME=baseline
FABRIC=switchless
PROFILE=base
SETUP=0
BUILD_ONLY=0
DOWNLOAD_ONLY=0
DRY_RUN=0
QUALIFICATION_RUN=0
FORCE=0
PASSTHRU=()
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --runtime) RUNTIME=${2:?missing runtime}; shift 2 ;;
    --fabric) FABRIC=${2:?missing fabric}; shift 2 ;;
    --profile) PROFILE=${2:?missing profile}; shift 2 ;;
    --setup) SETUP=1; shift ;;
    --build-only) BUILD_ONLY=1; shift ;;
    --download-only) DOWNLOAD_ONLY=1; shift ;;
    --qualification-run) QUALIFICATION_RUN=1; shift ;;
    --force-build) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '/^## Wrapper behavior/,/^The wrapper owns/p' "$ROOT/README.md"; exit 0 ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done
[[ "$RUNTIME" == baseline || "$RUNTIME" == b12x ]] || die "runtime must be baseline or b12x"
[[ "$FABRIC" == switched || "$FABRIC" == switchless ]] || die "fabric must be switched or switchless"
load_config "$CONFIG"
EUGR_DIR=$(cd "$EUGR_DIR" && pwd)
[[ -x "$EUGR_DIR/run-recipe.sh" || -f "$EUGR_DIR/run-recipe.sh" ]] || die "run-recipe.sh not found in $EUGR_DIR"

if ((SETUP || BUILD_ONLY)); then
  export DSV41_ALLOW_UNQUALIFIED_B12X=${DSV41_ALLOW_UNQUALIFIED_B12X:-NO}
  build_args=(--runtime "$RUNTIME")
  if [[ "$RUNTIME" == b12x && -n ${B12X_SOURCE_IMAGE:-} ]]; then
    build_args+=(--source-image "$B12X_SOURCE_IMAGE")
  fi
  ((FORCE == 0)) || build_args+=(--force)
  "$ROOT/tools/deepseek-v41-build.sh" "${build_args[@]}"
  image=$BASELINE_IMAGE; [[ "$RUNTIME" != b12x ]] || image=$B12X_IMAGE
  "$ROOT/runtime/distribute-image.sh" "$CONFIG" "$image"
  if [[ ! -f "$EUGR_DIR/.deepseek-v41-switchless-4x-installed" ]]; then
    "$ROOT/install.sh" "$EUGR_DIR" "$CONFIG"
  else
    note "eugr extension already installed; uninstall/reinstall to render config changes"
  fi
  ((BUILD_ONLY == 0)) || exit 0
fi

if ((DOWNLOAD_ONLY)); then
  exec "$ROOT/tools/deepseek-v41-download.sh" --config "$CONFIG"
fi

case "$RUNTIME:$PROFILE" in
  baseline:base|baseline:graphs|baseline:dspark|baseline:1m-validation)
    recipe="deepseek-v41-baseline-$PROFILE" ;;
  b12x:base|b12x:long|b12x:graphs|b12x:dspark)
    [[ ${DSV41_ALLOW_UNQUALIFIED_B12X:-NO} == YES ]] || die "B12X is unqualified; set explicit opt-in in config"
    if ((QUALIFICATION_RUN == 0)); then
      receipt="$ROOT/.receipts/b12x-qualified.env"
      [[ -f "$receipt" ]] || die "B12X has no PASS receipt; use --qualification-run only for evidence collection"
      receipt_status=$(sed -n 's/^STATUS=//p' "$receipt")
      receipt_model=$(sed -n 's/^MODEL_REVISION=//p' "$receipt")
      receipt_ranks=$(sed -n 's/^RANKS=//p' "$receipt")
      receipt_arch=$(sed -n 's/^ARCH=//p' "$receipt")
      receipt_image=$(sed -n 's/^IMAGE_ID=//p' "$receipt")
      receipt_fabric=$(sed -n 's/^FABRIC=//p' "$receipt")
      receipt_nccl=$(sed -n 's/^NCCL_LIBRARY_SHA256=//p' "$receipt")
      current_image_id=$(docker image inspect --format '{{.Id}}' "$B12X_IMAGE")
      [[ "$receipt_status" == PASS && "$receipt_model" == "$MODEL_REVISION" && \
         "$receipt_ranks" == 4 && "$receipt_arch" == sm121 && \
         "$receipt_image" == "$current_image_id" && "$receipt_fabric" == switchless && \
         "$receipt_nccl" == "$SWITCHLESS_NCCL_LIBRARY_SHA256" ]] || \
        die "B12X receipt is stale or incomplete"
    fi
    recipe="deepseek-v41-b12x-$PROFILE" ;;
  *) die "unsupported runtime/profile combination: $RUNTIME/$PROFILE" ;;
esac
[[ "$FABRIC" != switched ]] || recipe+="-switched"

cmd=(bash "$EUGR_DIR/run-recipe.sh" "$recipe" --no-ray "${PASSTHRU[@]}")
if ((DRY_RUN)); then quote_cmd "${cmd[@]}"; exit 0; fi
"$ROOT/tools/deepseek-v41-health.sh" --config "$CONFIG" --quick
cd "$EUGR_DIR"
exec "${cmd[@]}"
