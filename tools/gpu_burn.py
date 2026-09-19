#!/usr/bin/env python3
"""Short FP16 GEMM health gate; emits one JSON object."""
import json
import time

import torch

torch.set_float32_matmul_precision("high")
n = 8192
a = torch.randn((n, n), device="cuda", dtype=torch.float16)
b = torch.randn((n, n), device="cuda", dtype=torch.float16)
for _ in range(3):
    torch.mm(a, b)
torch.cuda.synchronize()
start = time.perf_counter()
count = 0
while time.perf_counter() - start < 15:
    torch.mm(a, b)
    count += 1
torch.cuda.synchronize()
elapsed = time.perf_counter() - start
tflops = count * 2 * n**3 / elapsed / 1e12
print(json.dumps({"device": torch.cuda.get_device_name(), "sm": "%d%d" % torch.cuda.get_device_capability(),
                  "iterations": count, "seconds": elapsed, "tflops": tflops}))
raise SystemExit(0 if tflops >= 50 else 1)
