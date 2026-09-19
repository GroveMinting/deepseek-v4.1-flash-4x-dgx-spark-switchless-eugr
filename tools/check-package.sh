#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mapfile -d '' scripts < <(find "$ROOT" -type f -name '*.sh' -not -path '*/vendor/*' -print0)
for script in "${scripts[@]}"; do bash -n "$script"; done
python3 -m compileall -q "$ROOT/tools" "$ROOT/tests" "$ROOT/switchless/nccl_smoke.py"

assert_absent() {
  local pattern=$1 path=$2 status
  if grep -R -q -- "$pattern" "$path"; then
    printf 'unexpected pattern %q found in %s\n' "$pattern" "$path" >&2
    return 1
  else
    status=$?
    ((status == 1)) || return "$status"
  fi
}

for pin in EUGR_COMMIT MODEL_REVISION VLLM_COMMIT FLASHINFER_COMMIT CUTLASS_COMMIT CCCL_COMMIT SPDLOG_COMMIT; do
  value=$(sed -n "s/^$pin=\"\([0-9a-f]*\)\"/\1/p" "$ROOT/VERSIONS.lock")
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || { echo "$pin is not a full commit" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 "$ROOT/tools/render-recipes.py" --config "$ROOT/config/cluster.env.example" --out "$tmp"
[[ $(find "$tmp" -type f -name '*.yaml' | wc -l) -eq 16 ]]
assert_absent '__[A-Z0-9_]*__' "$tmp"
assert_absent '45,48' "$tmp"
grep -R -q 'dba1be0a40aa45a94ad051997016db3960a90277' "$tmp"
for recipe in "$tmp"/*.yaml; do
  if [[ "$recipe" == *-switched.yaml ]]; then
    assert_absent 'LD_PRELOAD' "$recipe"
    assert_absent 'NCCL_SWITCHLESS_RING_ONLY' "$recipe"
  else
    grep -q 'NCCL_SWITCHLESS_RING_ONLY: "1"' "$recipe"
    grep -q 'LD_PRELOAD' "$recipe"
  fi
done
grep -R -q 'max_num_seqs: 1' "$tmp"

if command -v shellcheck >/dev/null; then
  shellcheck -x -P SCRIPTDIR "${scripts[@]}"
fi
python3 -m unittest discover -s "$ROOT/tests" -v
echo "static package checks passed"
