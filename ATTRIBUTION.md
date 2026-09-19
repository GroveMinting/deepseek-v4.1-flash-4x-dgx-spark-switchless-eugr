# Attribution and licensing boundaries

This repository's orchestration, safety guards, eugr templates, tests and
runbooks are MIT licensed by its contributors.

Tony D. / Tech2wild's DeepSeek V4.1 repository provides the model-specific
boot10 vLLM patch set, overlay build sequence, DSpark/graph configuration,
Engram-on-disk behavior, local-row staging tool and measured reference. It is
MIT licensed; the code is fetched from its original repository during setup.
See `LICENSES/TONY-MIT.txt`.

Alex Ellis / OpenFaaS Ltd's work provides the physical switchless ring and
validation design. The pinned binary comes from `alexellis/switchless-nccl`
v0.0.1 and is verified by archive and library SHA-256. Alex's work is MIT
licensed; see `LICENSES/ALEX-MIT.txt` and the release for bundled notices.

eugr/spark-vllm-docker, vLLM, B12X, NCCL, FlashInfer, PyTorch, CUDA components,
and the DeepSeek model retain their own licenses. This repository does not
relicense them. The official DeepSeek-V4.1-Flash model card currently states
MIT; operators remain responsible for reviewing the pinned model revision.
