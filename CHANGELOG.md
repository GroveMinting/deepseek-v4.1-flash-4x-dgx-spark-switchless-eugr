# Changelog

## 0.1.0 — 2026-09-18

- Add official DeepSeek-V4.1-Flash TP4 recipes for four DGX Sparks.
- Make the four-cable switchless RoCE ring the canonical and default fabric.
- Retain conventional switched RoCE recipes only as explicit diagnostic
  fallbacks with a `-switched` suffix.
- Add Tony boot10-derived baseline build, disk-Engram staging and DSpark K=5.
- Add fail-closed B12X candidate lane and machine-readable qualification receipt.
- Add guarded fabric setup, rollback, health, smoke, image parity, NCCL receipt
  and CI checks.
