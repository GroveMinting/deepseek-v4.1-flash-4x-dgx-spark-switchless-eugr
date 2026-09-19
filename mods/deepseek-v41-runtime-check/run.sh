#!/usr/bin/env bash
set -euo pipefail

RECEIPT=/opt/dsv41/runtime.env
[[ -r "$RECEIPT" ]] || {
  echo "custom-image receipt missing: $RECEIPT; refusing to patch a stock image at runtime" >&2
  exit 1
}
# shellcheck source=/dev/null
source "$RECEIPT"
[[ ${MODEL_REVISION:-} == "${DSV41_EXPECTED_MODEL_REVISION:-}" ]] || {
  echo "model revision mismatch in custom image receipt" >&2; exit 1;
}
[[ ${VLLM_COMMIT:-} == e47aa780bccf59f59dfa2cbb18e17a10b4fe69ba || \
   ${RUNTIME_LANE:-} == b12x-candidate ]] || {
  echo "unexpected baseline vLLM commit: ${VLLM_COMMIT:-missing}" >&2; exit 1;
}
if [[ -n ${LD_PRELOAD:-} ]]; then
  [[ -r /opt/nccl-switchless/libnccl.so.2 ]] || {
    echo "switchless NCCL library missing" >&2; exit 1;
  }
  actual=$(sha256sum /opt/nccl-switchless/libnccl.so.2 | awk '{print $1}')
  [[ "$actual" == 78cb83871792ec57d763d142e4cae26fc754ae284bcc81dcb2a7d50e17d4fa57 ]] || {
    echo "switchless NCCL hash mismatch: $actual" >&2; exit 1;
  }
fi
echo "DeepSeek V4.1 immutable runtime receipt verified (${RUNTIME_LANE:-unknown})"
