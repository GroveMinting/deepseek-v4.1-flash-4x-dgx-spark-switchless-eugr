# B12X V4.1 readiness

## Current conclusion

B12X is not yet proven ready for DeepSeek-V4.1-Flash on four DGX Sparks. It is
useful as a candidate lane, but the reference lane in this repository is the
Tony boot10-derived upstream-vLLM path on the same switchless ring.

The evidence is promising but not equivalent:

- B12X has a dedicated `validation/deepseek_v41` harness and exact-token parity
  checks. Its native KV allocation artifact reports TP4, disk Engram, DSpark K5,
  successful HTTP requests, and a 65,550-token prompt.
- That receipt is a local SM120/multi-GPU result, not four GB10/SM121 nodes.
- The B12X artifact itself lists “full native vLLM qualification” as remaining.
- B12X issue #182 documents an invalid FC2 tile on GB10/SM121 in the version
  shipped by eugr for V4-0731; a proposed patch made a two-Spark run work. That
  does not establish four-Spark V4.1 readiness.
- Upstream vLLM SM120/121 issues cover page/block geometry and DSpark long-prompt
  behavior, so speculation is gated until the no-speculation baseline passes.

## Candidate construction

Do not patch eugr's stock image during container startup. Build a B12X image
from the exact candidate commits, then wrap it immutably:

```bash
# Example using a current eugr checkout and local-inference-lab vLLM source:
git clone https://github.com/local-inference-lab/vllm.git /opt/vllm-b12x-candidate
git -C /opt/vllm-b12x-candidate checkout <reviewed-commit>
./build-and-copy.sh --rebuild-vllm \
  --tag vllm-dsv41-switchless-b12x-source:<commit> \
  --vllm-source-dir /opt/vllm-b12x-candidate

export DSV41_ALLOW_UNQUALIFIED_B12X=YES
./tools/deepseek-v41-build.sh --runtime b12x \
  --source-image vllm-dsv41-switchless-b12x-source:<commit>
```

Record resolved vLLM, B12X, FlashInfer, CUTLASS-DSL and base image commits in
the test receipt. A moving `master` or `latest` tag is never a promotion input.

## Qualification order

1. Pass the four-rank switchless NCCL collective gate.
2. Baseline runtime on switchless, eager/no speculation, and save its token
   reference.
3. B12X candidate on the same switchless fabric and profile; require exact
   token-sequence parity.
4. Long eager profile at 300K/C1.
5. B12X CUDA graphs at 64K without speculation.
6. DSpark K5 at 64K/C1, then longer context if locally required.

Use the switched recipes only to isolate a failure. A switched B12X pass is not
a switchless qualification receipt.

Gate the candidate image itself before its first model run:

```bash
IMAGE="vllm-dsv41-switchless-eugr:b12x-candidate" \
  ./switchless/nccl-gate.sh --config config/cluster.env
```

To start a deliberately unqualified run, set
`DSV41_ALLOW_UNQUALIFIED_B12X=YES` in `config/cluster.env`, reinstall the rendered
recipes, and use:

```bash
./run-deepseek-v41.sh --config config/cluster.env \
  --runtime b12x --fabric switchless --profile base --qualification-run -d
./tools/deepseek-v41-qualify.sh --config config/cluster.env \
  --runtime b12x --fabric switchless \
  --stage base-64k --reference .receipts/baseline-reference.json

# Repeat with the long, graphs and dspark recipes/stage names, then:
./tools/deepseek-v41-qualify.sh \
  --config config/cluster.env --runtime b12x --fabric switchless --promote
```

## Promotion receipt

A PASS receipt must contain:

- four distinct nodes and ranks, all SM121;
- official model revision `dba1be0a40aa45a94ad051997016db3960a90277`;
- exact container digest and all resolved source commits;
- image parity on all ranks and Engram range receipts;
- GPU burn results over 50 TFLOPS per rank;
- a passing four-rank switchless NCCL collective receipt;
- no-speculation token-sequence parity against the baseline;
- text, vision and tool-call success;
- 64K base and 300K long-profile results;
- CUDA graph results; and only then DSpark K5 metrics.

The wrapper accepts B12X outside `--qualification-run` only after a local PASS
receipt exists. This is a guardrail, not an upstream readiness claim.
