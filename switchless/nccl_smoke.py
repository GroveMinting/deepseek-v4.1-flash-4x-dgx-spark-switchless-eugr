import os
import socket
import time

import torch
import torch.distributed as dist

dist.init_process_group("nccl")
rank = dist.get_rank()
world = dist.get_world_size()
assert world == 4, f"expected world size 4, got {world}"
x = torch.full((15_360,), rank + 1, device="cuda", dtype=torch.float32)  # 60 KiB
for _ in range(10):
    x.fill_(rank + 1)
    dist.all_reduce(x)
torch.cuda.synchronize()
start = time.perf_counter()
for _ in range(100):
    x.fill_(rank + 1)
    dist.all_reduce(x)
torch.cuda.synchronize()
elapsed = time.perf_counter() - start
expected = sum(range(1, world + 1))
assert torch.all(x == expected), (rank, x[0].item(), expected)
print(f"rank={rank} host={socket.gethostname()} 60KiB-allreduce-us={elapsed * 1e6 / 100:.1f}", flush=True)
dist.barrier()
dist.destroy_process_group()
