#!/usr/bin/env bash
set -euo pipefail
container=${1:-}
if [[ -z "$container" ]]; then
  container=$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /dsv41/ {print $1; exit}')
fi
[[ -n "$container" ]] || { echo "no DeepSeek V4.1 container found; pass its name" >&2; exit 1; }
docker exec "$container" bash -lc '
  set -eu
  cat /opt/dsv41/runtime.env
  sha256sum /opt/nccl-switchless/libnccl.so.2
  python - <<"PY"
import pathlib, vllm
root = pathlib.Path(vllm.__file__).resolve().parent
print("vllm_root=" + str(root))
for rel in (
 "models/deepseek_v4_1/common/engram.py",
 "models/deepseek_v4_1/nvidia/model_state.py",
 "model_executor/model_loader/weight_utils.py",
 "models/deepseek_v4_1/attention.py",
 "models/deepseek_v4_1/nvidia/flashinfer_sparse.py",
 "v1/attention/backends/mla/sparse_swa.py",
 "model_executor/layers/sparse_attn_indexer.py",
):
    path = root / rel
    print(f"{rel}={path.stat().st_size}")
PY'
