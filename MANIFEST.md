# Distribution manifest

The source archive contains recipes, orchestration, validation tools,
documentation and license notices. It intentionally excludes:

- the roughly 510 GB checkpoint;
- Docker images and caches;
- Tony's fetched patch/build sources;
- the switchless NCCL binary (downloaded from a hash-pinned release);
- Hugging Face, SSH or source-control credentials;
- rank-specific Engram data and local qualification receipts.

Local-only paths are listed in `.gitignore`: `vendor/`, `build/`,
`.resolved-refs`, `.receipts/`, `config/cluster.env`, `rendered-recipes/`, and
archive outputs.
