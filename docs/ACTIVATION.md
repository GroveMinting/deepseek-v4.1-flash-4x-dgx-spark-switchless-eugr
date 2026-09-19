# Activation and acceptance runbook

Stop at the first failed gate and retain its logs. Do not change the runtime,
fabric, speculation mode, and context length in the same experiment.

The canonical recipe names in this project are switchless. Switched recipes
exist only as `-switched` diagnostic fallbacks.

## 0. Assemble the pinned runtime

1. Copy `config/cluster.env.example` to `config/cluster.env`.
2. Confirm management and ConnectX interface names on every Spark.
3. Run `bash tools/check-package.sh`.
4. Build with
   `run-deepseek-v41.sh --setup --runtime baseline --build-only`.
5. Run `run-deepseek-v41.sh --download-only`.
6. Put the printed checkpoint snapshot path in `MODEL_DIR`.
7. Confirm the exact model revision, all 48 shards, and identical image IDs on
   all four ranks.

Acceptance:

- immutable custom image;
- official model revision
  `dba1be0a40aa45a94ad051997016db3960a90277`;
- 48 checkpoint shards on every rank;
- no runtime patching of a stock image;
- matching image IDs across all ranks.

## 1. Hardware health

```bash
./tools/deepseek-v41-health.sh \
  --config config/cluster.env \
  --burn
```

The 15-second FP16 test detects a GB10 that has latched below its expected
clock without reporting an obvious driver error.

Acceptance:

- one SM121 GPU per rank;
- no competing GPU compute processes;
- at least 50 TFLOPS on every rank.

## 2. Switchless fabric

Use four passive 100 GbE QSFP28 DACs in the exact ring documented in
`NETWORKING.md`.

```bash
./switchless/fabric-setup.sh --config config/cluster.env
```

Review the dry run and physically trace the four cables. Change
`I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES` to `YES`, then run:

```bash
./switchless/fabric-setup.sh --config config/cluster.env --apply
./switchless/fabric-verify.sh --config config/cluster.env
./switchless/nccl-gate.sh --config config/cluster.env
```

Acceptance:

- eight active RoCE v2 GIDs;
- exact netdev-to-HCA mappings and `/24` addresses;
- MTU 9000 on all eight rails;
- successful jumbo packets on all four physical edges;
- a successful four-rank GPU all-reduce through the pinned switchless NCCL
  library.

Ping alone is not sufficient.

## 3. Baseline base profile

Launch the canonical switchless recipe:

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --runtime baseline \
  --fabric switchless \
  --profile base \
  -d
```

The first boot discovers rank-specific Engram row ranges. Copy
`config/engram-ranges.example` to `config/engram-ranges`, enter both ranges
from every rank, stop the cluster, and run:

```bash
./tools/deepseek-v41-stage-engram.sh \
  --config config/cluster.env \
  --ranges config/engram-ranges
```

Restart the base profile, then run:

```bash
./tools/deepseek-v41-smoke.sh http://127.0.0.1:8000
./tools/deepseek-v41-qualify.sh \
  --config config/cluster.env \
  --runtime baseline
```

Acceptance:

- eager 300K/C1 boot;
- exact literal response;
- non-empty vision response;
- correct tool call;
- matching image IDs;
- byte-sampled Engram copies on local NVMe;
- saved baseline token-sequence reference.

## 4. CUDA graphs without speculation

Stop the base profile and launch `--profile graphs` on the same switchless
fabric. This isolates graph capture from speculation. The capture set is:

```text
[5,6,10,12,15,18,20,24,25,30,35,36,40,42,48]
```

Acceptance:

- graph capture completes on all four ranks;
- the API suite passes;
- repeated output is not garbled;
- no new NCCL or transport errors appear.

## 5. DSpark K=5

Stop the graph profile and launch `--profile dspark`. Keep concurrency at one.
The recipe uses block rejection sampling and disables adaptive verification to
match the reference boot10 operating point.

Acceptance:

- draft layers load;
- CUDA graph capture completes;
- text, vision, and tool-call tests pass;
- metrics show speculative activity and acceptance;
- 20 repeated requests complete without corrupted output.

Only then test 2, 4, and 8 concurrent sequences as local overrides.

## 6. 1M proof profile

Launch `--profile 1m-validation` only after the 300K ladder passes. It is eager,
concurrency 1, and has no speculation.

The earlier reference run demonstrated allocation, but the widest decode case
was not rerun after the top-k fix. Acceptance here is evidence collection, not
production status.

## 7. B12X candidate

Follow `B12X-READINESS.md`. Compare it with the saved switchless baseline while
holding the model revision, fabric, context, prompts, and concurrency constant.

Use `--qualification-run` until a complete PASS receipt exists. Never replace
the baseline image tag.

Promotion requires:

- four-rank SM121 health evidence;
- image parity;
- the switchless NCCL gate;
- exact token-sequence parity with the baseline;
- base, long, graph, and DSpark stage receipts;
- text, vision, and tool-call success.

## Diagnostic switched fallback

Use the switched fabric only to isolate a suspected direct-ring or NCCL
failure:

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --runtime baseline \
  --fabric switched \
  --profile base \
  -d
```

A switched success does not promote or qualify the switchless path. Return to
the ring, repeat its collective gate, and reproduce the model result before
recording a switchless PASS.

## Rollback

Stop eugr first.

```bash
./switchless/fabric-rollback.sh \
  --config config/cluster.env \
  --apply

./uninstall.sh ../spark-vllm-docker
```

The fabric rollback removes only this project's addresses and firewall rules.
Uninstall restores collided eugr files from the timestamped backup. Custom
images, model files, caches, Engram data, and qualification receipts are not
deleted.

