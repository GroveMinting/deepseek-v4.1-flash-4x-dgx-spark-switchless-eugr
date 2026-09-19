#!/usr/bin/env bash
set -euo pipefail

[[ ${DSV41_RUNTIME_LANE:-} == b12x-candidate ]] || {
  echo "B12X guard attached to a non-candidate runtime" >&2; exit 1;
}
[[ ${DSV41_ALLOW_UNQUALIFIED_B12X:-NO} == YES ]] || {
  echo "B12X V4.1 on four SM121 Sparks is not qualified." >&2
  echo "For an instrumented qualification run, set DSV41_ALLOW_UNQUALIFIED_B12X=YES in config and reinstall." >&2
  exit 1
}
python - <<'PY'
import torch
major, minor = torch.cuda.get_device_capability()
if (major, minor) != (12, 1):
    raise SystemExit(f"B12X candidate requires GB10/SM121, got SM{major}{minor}")
print("B12X candidate gate: explicit unqualified opt-in accepted on SM121")
PY
