# DeepSeek-V4.1-Flash on 4× DGX Spark — switchless eugr

[![CI](https://github.com/GroveMinting/deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr/actions/workflows/ci.yml/badge.svg)](https://github.com/GroveMinting/deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/GroveMinting/deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr?include_prereleases&sort=semver)](https://github.com/GroveMinting/deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Target: 4× DGX Spark](https://img.shields.io/badge/target-4%C3%97%20DGX%20Spark-76B900?logo=nvidia&logoColor=white)](#requirements)
[![Fabric: Switchless RoCE](https://img.shields.io/badge/fabric-switchless%20RoCE-0A66C2)](docs/NETWORKING.md)
[![Runtime: eugr + vLLM](https://img.shields.io/badge/runtime-eugr%20%2B%20vLLM-6F42C1)](https://github.com/eugr/spark-vllm-docker)

**Switchless-first · TP4 · official MXFP4 checkpoint · disk-backed Engram · fail-closed B12X qualification**

Run the official
[`deepseek-ai/DeepSeek-V4.1-Flash`](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
MXFP4 checkpoint across four NVIDIA DGX Sparks using
[`eugr/spark-vllm-docker`](https://github.com/eugr/spark-vllm-docker), tensor
parallelism 4, disk-backed Engram tables, and a four-cable switchless RoCE
ring.

Switchless networking is the defining path in this project:

- it is the wrapper default;
- canonical recipe names are switchless;
- the runtime image contains a hash-verified hardened switchless NCCL build;
- fabric setup is dry-run-first and reversible;
- a four-rank GPU collective must pass before the model is launched.

A conventional switched RoCE path is retained only as an explicitly named
diagnostic fallback.

> [!IMPORTANT]
> This repository provides a reproducible implementation and qualification
> ladder. It does not claim that DeepSeek-V4.1-Flash, B12X, or every performance
> profile has already passed four-Spark hardware qualification. The baseline
> and B12X paths remain gated by evidence collected on the target cluster.

## Architecture

Rank 0 is the eugr head and OpenAI-compatible API node. Management Ethernet or
Wi-Fi carries SSH, Gloo, bootstrap, and client traffic. Both ConnectX-7 ports
on every Spark are dedicated to the NCCL ring.

| Edge | First endpoint | Second endpoint | Fabric subnet |
|---|---|---|---|
| 0–1 | node 0 port 1 | node 1 port 1 | `10.10.10.0/24` |
| 1–2 | node 1 port 0 | node 2 port 0 | `10.10.20.0/24` |
| 2–3 | node 2 port 1 | node 3 port 1 | `10.10.30.0/24` |
| 3–0 | node 3 port 0 | node 0 port 0 | `10.10.40.0/24` |

The topology follows
[`alexellis/glm-5.3-flash-4x-dgx-spark-switchless`](https://github.com/alexellis/glm-5.3-flash-4x-dgx-spark-switchless).
The image embeds the pinned `switchless-nccl` v0.0.1 release and verifies both
the archive and `libnccl.so.2` SHA-256 values before use.

## Runtime lanes

| Runtime | Purpose | Status |
|---|---|---|
| Tony boot10-derived vLLM | Reference MXFP4, disk-Engram and DSpark path | Qualification baseline |
| B12X candidate | Candidate optimized kernels | Fail-closed until a matching four-node SM121 receipt passes |

Both lanes render switchless recipes as their canonical names. Diagnostic
switched variants use the `-switched` suffix and are selected only with
`--fabric switched`.

## Included safeguards

- Immutable model, eugr, vLLM, FlashInfer, CUTLASS, CCCL, spdlog, base-image,
  and switchless-NCCL inputs.
- Official model revision and 48-shard verification on all four ranks.
- Identical image distribution with image-ID comparison.
- One SM121 GPU per node and idle-GPU checks before launch.
- A short FP16 burn gate that detects the GB10 low-clock state.
- Dry-run-first switchless configuration with explicit confirmation.
- MTU, address, RoCE GID, HCA mapping, jumbo-packet, and NCCL collective gates.
- Rank-local Engram staging with byte-sample verification.
- Text, vision, tool-call, and repeated-request qualification.
- Reversible eugr installation and switchless network rollback.
- A fail-closed B12X qualification and promotion receipt.

## Requirements

- Four NVIDIA DGX Sparks with one GB10/SM121 GPU each.
- Matching DGX OS, NVIDIA driver, Docker, and NVIDIA Container Toolkit.
- Passwordless SSH from rank 0 to all four nodes.
- Four passive 100 GbE QSFP28 DACs connected in the documented ring.
- A separate management network that remains connected during setup.
- MTU 9000 support on both ConnectX interfaces.
- Approximately 510 GB for the official checkpoint wherever it is exposed to
  each rank.
- Approximately 48 GB of local NVMe per Spark for its staged Engram rows.
- Bash, Git, Python 3, Docker, `ssh`, and `scp` on rank 0.

## Quick start

Run the following from rank 0.

### 1. Clone the pinned eugr revision and this project

```bash
git clone https://github.com/eugr/spark-vllm-docker.git
git -C spark-vllm-docker checkout acd5d2a253704ad71096c5f23ac45e7cf57442af

git clone https://github.com/GroveMinting/deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr.git
cd deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr
```

### 2. Configure the four Sparks

```bash
cp config/cluster.env.example config/cluster.env
nano config/cluster.env
```

Verify every management address, interface, HCA, and direct-link IP. Interface
names in the example are not assumptions:

```bash
ip -br link
ls /sys/class/infiniband
```

### 3. Check the package

```bash
sudo apt-get update
sudo apt-get install -y shellcheck python3-yaml
bash ./tools/check-package.sh
```

This renders and validates all 16 recipes: eight canonical switchless recipes
and eight explicitly named switched fallbacks.

### 4. Build, distribute, and install the baseline

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --setup \
  --runtime baseline \
  --build-only
```

`--build-only` is required here so setup does not continue into a model
launch before the checkpoint and fabric are ready. The command builds
`vllm-dsv41-switchless-eugr:boot10`, loads the identical image on all four
nodes, verifies image parity, and installs the rendered recipes into eugr.

### 5. Download and verify the official checkpoint

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --download-only
```

The downloader pins revision
`dba1be0a40aa45a94ad051997016db3960a90277`, verifies all 48 shards on every
rank, and prints the resolved snapshot path. Put that path in `MODEL_DIR`
inside `config/cluster.env`.

### 6. Run the GPU health gate

```bash
./tools/deepseek-v41-health.sh \
  --config config/cluster.env \
  --burn
```

Every rank must report one idle SM121 GPU and at least 50 FP16 TFLOPS during
the short burn.

### 7. Configure and prove the switchless ring

First inspect the proposed network changes:

```bash
./switchless/fabric-setup.sh --config config/cluster.env
```

Trace all four physical cables and compare the displayed interfaces, HCAs, and
addresses with `config/cluster.env`. Then change:

```text
I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES="YES"
```

Apply and verify:

```bash
./switchless/fabric-setup.sh --config config/cluster.env --apply
./switchless/fabric-verify.sh --config config/cluster.env
./switchless/nccl-gate.sh --config config/cluster.env
```

Do not proceed on ping results alone. The four-rank GPU all-reduce gate is the
transport acceptance test.

### 8. Launch the canonical base recipe

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --runtime baseline \
  --fabric switchless \
  --profile base \
  -d
```

The first boot discovers the two Engram row ranges required by each rank.
Capture them from all four logs, stop the cluster, and stage the local rows:

```bash
cp config/engram-ranges.example config/engram-ranges
nano config/engram-ranges

./tools/deepseek-v41-stage-engram.sh \
  --config config/cluster.env \
  --ranges config/engram-ranges
```

Restart the same base profile and run:

```bash
./tools/deepseek-v41-smoke.sh http://127.0.0.1:8000
```

The API is served from rank 0 on port 8000 by default with model name
`deepseek-v4.1-flash`.

## Qualification order

Change one variable at a time and retain the logs from every stage:

1. Switchless NCCL collective gate.
2. Baseline `base`: eager, 300K context, no speculation, concurrency 1.
3. Baseline `graphs`: fixed CUDA graph set, no speculation.
4. Baseline `dspark`: the same graph set plus DSpark K=5.
5. Baseline `1m-validation`: evidence collection only.
6. B12X `base` against the saved baseline token sequence.
7. B12X `long`, then `graphs`, then `dspark`.

Use `--fabric switched` only to isolate a suspected ring or NCCL problem. A
successful switched run does not qualify the switchless project.

## Profiles

| Runtime | Profile | Purpose |
|---|---|---|
| `baseline` | `base` | Eager, 300K context, no speculation, concurrency 1 |
| `baseline` | `graphs` | Fixed CUDA graphs without speculation |
| `baseline` | `dspark` | CUDA graphs with DSpark K=5 |
| `baseline` | `1m-validation` | Eager 1M allocation and decode evidence |
| `b12x` | `base` | Candidate eager baseline |
| `b12x` | `long` | Candidate 300K context test |
| `b12x` | `graphs` | Candidate CUDA graph test |
| `b12x` | `dspark` | Candidate DSpark K=5 test |

The 1M profile is not a production default. Initial concurrency remains one
until the complete ladder passes.

## B12X policy

B12X is deliberately not the default. A qualification run requires:

1. a separately built, pinned B12X source image;
2. `DSV41_ALLOW_UNQUALIFIED_B12X="YES"` in the cluster configuration;
3. reinstallation of the rendered recipes; and
4. `--qualification-run` on the wrapper.

Normal B12X launches remain blocked until a local PASS receipt matches the
official model revision, four SM121 ranks, and the current candidate image ID.
See [`docs/B12X-READINESS.md`](docs/B12X-READINESS.md).

## Wrapper behavior

```text
./run-deepseek-v41.sh [wrapper options] [arguments passed to run-recipe.sh]

  --setup                 build, distribute, and install the selected runtime
  --build-only            stop after build, distribution, and installation
  --download-only         download and verify the pinned official checkpoint
  --runtime baseline|b12x
  --fabric switchless|switched
  --profile PROFILE       choose a runtime-compatible profile
  --config FILE           cluster configuration; default config/cluster.env
  --qualification-run     allow evidence collection for unqualified B12X
  --force-build           rebuild the selected image
  --dry-run               print the final eugr command without executing it
```

The wrapper owns setup because generic eugr `run-recipe.sh --setup` may
replace the custom image. It always launches the four-node path with
`--no-ray`. Unknown arguments such as `-d` are passed through to eugr.

## Rollback

Stop eugr before changing the fabric:

```bash
./switchless/fabric-rollback.sh \
  --config config/cluster.env \
  --apply

./uninstall.sh ../spark-vllm-docker
```

The fabric rollback removes only this project's addresses and firewall rules,
then returns both rails to NetworkManager. Uninstall restores any eugr files
that were replaced. Neither command deletes images, model files, caches,
Engram data, or qualification receipts.

## Repository layout

```text
.github/workflows/       static CI
config/                  cluster and Engram configuration examples
docs/                    activation, networking, and B12X qualification
mods/                    fail-closed eugr runtime checks
recipes/                 recipe templates
runtime/                 immutable image construction and distribution
switchless/              fabric setup, verification, NCCL gate, and rollback
tests/                    recipe and wrapper tests
tools/                    model, health, Engram, smoke, and qualification tools
VERSIONS.lock            authoritative upstream pins and hashes
run-deepseek-v41.sh       operator entry point
```

## Sources and limitations

- [`eugr/spark-vllm-docker`](https://github.com/eugr/spark-vllm-docker)
  supplies the multi-node launcher and recipe contract.
- [`tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark`](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark)
  supplies the boot10-derived vLLM patch lineage, disk-Engram method, graph
  sizes, DSpark settings, and measured health threshold.
- [`alexellis/glm-5.3-flash-4x-dgx-spark-switchless`](https://github.com/alexellis/glm-5.3-flash-4x-dgx-spark-switchless)
  supplies the demonstrated four-Spark direct-link topology.
- [`alexellis/switchless-nccl`](https://github.com/alexellis/switchless-nccl)
  supplies the pinned hardened NCCL build.
- [`local-inference-lab/b12x`](https://github.com/local-inference-lab/b12x)
  supplies the candidate optimized kernel path.

Four Sparks are not a transparent 512 GB memory pool. Engram tables remain on
local disk, and the full model/fabric composition must pass the included
qualification gates before production use.

## License

This project is licensed under the [MIT License](LICENSE). Upstream code,
images, model weights, and binary artifacts retain their own licenses. See
[`ATTRIBUTION.md`](ATTRIBUTION.md) and [`LICENSES/`](LICENSES/).
