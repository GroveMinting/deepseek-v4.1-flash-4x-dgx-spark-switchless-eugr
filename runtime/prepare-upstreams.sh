#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "$ROOT/runtime/common.sh"
load_versions

VENDOR="$ROOT/vendor/tony-v41"
PATCH_OUT="$ROOT/build/runtime-context/patch"
mkdir -p "$ROOT/vendor" "$PATCH_OUT" "$ROOT/.receipts"

if [[ ! -d "$VENDOR/.git" ]]; then
  git clone "$TONY_REPOSITORY" "$VENDOR"
else
  [[ -z $(git -C "$VENDOR" status --porcelain) ]] || die "dirty vendor checkout: $VENDOR"
  [[ $(git -C "$VENDOR" remote get-url origin) == "$TONY_REPOSITORY" ]] || die "unexpected Tony origin"
  git -C "$VENDOR" fetch --prune origin
fi
git -C "$VENDOR" checkout --detach "$TONY_REF"
TONY_COMMIT=$(git -C "$VENDOR" rev-parse HEAD)

# These prefixes identify the published boot10 whole-file patch set. Full
# SHA-256 values are captured below so all four final images can be compared.
declare -A EXPECTED_MD5_PREFIX=(
  [engram.py]=c0329107
  [model_state.py]=0a14bee6
  [weight_utils.py]=7e1027f1
  [attention.py]=da9ef196
  [flashinfer_sparse.py]=af0f8447
  [sparse_swa.py]=cc419353
  [sparse_attn_indexer.py]=a9b73756
)

find_patch() {
  local name=$1 candidate
  for candidate in "$VENDOR/patch/$name" "$VENDOR/patches/$name"; do
    [[ ! -f "$candidate" ]] || { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

for name in "${!EXPECTED_MD5_PREFIX[@]}"; do
  src=$(find_patch "$name") || die "Tony boot10 patch not found: $name"
  actual=$(md5sum "$src" | awk '{print $1}')
  [[ "$actual" == "${EXPECTED_MD5_PREFIX[$name]}"* ]] || \
    die "boot10 patch drift for $name: got $actual"
  install -m 0644 "$src" "$PATCH_OUT/$name"
done
(cd "$PATCH_OUT" && sha256sum ./*.py | sort > SHA256SUMS)

ENGRAM_TOOL="$VENDOR/tools/engram_local.py"
[[ -f "$ENGRAM_TOOL" ]] || die "Tony Engram staging tool missing: $ENGRAM_TOOL"
install -m 0755 "$ENGRAM_TOOL" "$ROOT/build/runtime-context/engram_local.py"

{
  printf 'TONY_COMMIT=%q\n' "$TONY_COMMIT"
  printf 'TONY_PATCHSET=%q\n' "$TONY_PATCHSET"
  printf 'VLLM_COMMIT=%q\n' "$VLLM_COMMIT"
  printf 'MODEL_REVISION=%q\n' "$MODEL_REVISION"
  printf 'FLASHINFER_COMMIT=%q\n' "$FLASHINFER_COMMIT"
  printf 'PREPARED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$ROOT/.resolved-refs"
note "prepared Tony boot10 inputs; resolved Tony commit $TONY_COMMIT"
note "full patch hashes: $PATCH_OUT/SHA256SUMS"
