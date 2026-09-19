#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
quote_cmd() { printf '%q ' "$@"; printf '\n'; }

load_versions() {
  # shellcheck source=../VERSIONS.lock
  source "$PROJECT_ROOT/VERSIONS.lock"
}

load_config() {
  local file=${1:?config path required}
  [[ -f "$file" ]] || die "config not found: $file"
  # Administrator-controlled shell fragment.
  # shellcheck source=/dev/null
  source "$file"
  : "${SSH_USER:?set SSH_USER}" "${NODE0_MGMT:?set NODE0_MGMT}"
  : "${NODE1_MGMT:?set NODE1_MGMT}" "${NODE2_MGMT:?set NODE2_MGMT}"
  : "${NODE3_MGMT:?set NODE3_MGMT}" "${MGMT_IF:?set MGMT_IF}"
  SSH_PORT=${SSH_PORT:-22}
  MTU=${MTU:-9000}
  EUGR_DIR=${EUGR_DIR:-$PROJECT_ROOT/../spark-vllm-docker}
  MODEL_CACHE=${MODEL_CACHE:-/home/$SSH_USER/.cache/huggingface}
  ENGRAM_LOCAL_ROOT=${ENGRAM_LOCAL_ROOT:-$MODEL_CACHE/engram-local/DeepSeek-V4.1-Flash}
  ENGRAM_CONTAINER_ROOT=${ENGRAM_CONTAINER_ROOT:-/root/.cache/huggingface/engram-local/DeepSeek-V4.1-Flash}
  BASELINE_IMAGE=${BASELINE_IMAGE:-vllm-dsv41-switchless-eugr:boot10}
  B12X_IMAGE=${B12X_IMAGE:-vllm-dsv41-switchless-eugr:b12x-candidate}
  [[ "$MTU" == 9000 ]] || die "RoCE profiles require MTU=9000"
  local value
  for value in "$NODE0_MGMT" "$NODE1_MGMT" "$NODE2_MGMT" "$NODE3_MGMT"; do
    [[ "$value" =~ ^[0-9A-Fa-f:.]+$ ]] || die "unsafe management IP: $value"
  done
  for value in "$MGMT_IF" "${SWITCHED_HCA:-}" "${F1_IF:-}" "${F0_IF:-}" \
      "${F1_HCA:-}" "${F0_HCA:-}"; do
    [[ -z "$value" || "$value" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "unsafe interface/HCA: $value"
  done
  [[ "$SSH_USER" =~ ^[A-Za-z0-9_.-]+$ ]] || die "unsafe SSH_USER"
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "invalid SSH_PORT"
  for value in "$MODEL_CACHE" "$ENGRAM_LOCAL_ROOT" "$ENGRAM_CONTAINER_ROOT"; do
    [[ "$value" =~ ^/[A-Za-z0-9_./:@+-]+$ ]] || die "unsafe remote path: $value"
  done
  NODES=("$NODE0_MGMT" "$NODE1_MGMT" "$NODE2_MGMT" "$NODE3_MGMT")
  SSH_OPTS=(-p "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12)
  [[ -z ${SSH_KEY:-} ]] || SSH_OPTS+=(-i "$SSH_KEY")
}

require_switchless_config() {
  : "${F1_IF:?set F1_IF}" "${F0_IF:?set F0_IF}"
  : "${F1_HCA:?set F1_HCA}" "${F0_HCA:?set F0_HCA}" "${GID_INDEX:?set GID_INDEX}"
  : "${NODE0_F1:?set NODE0_F1}" "${NODE0_F0:?set NODE0_F0}"
  : "${NODE1_F1:?set NODE1_F1}" "${NODE1_F0:?set NODE1_F0}"
  : "${NODE2_F1:?set NODE2_F1}" "${NODE2_F0:?set NODE2_F0}"
  : "${NODE3_F1:?set NODE3_F1}" "${NODE3_F0:?set NODE3_F0}"
  [[ "$MGMT_IF" != "$F0_IF" && "$MGMT_IF" != "$F1_IF" && "$F0_IF" != "$F1_IF" ]] || \
    die "management, f0, and f1 interfaces must be distinct"
  [[ "$F0_HCA" != "$F1_HCA" ]] || die "F0_HCA and F1_HCA must differ"
  [[ "$GID_INDEX" =~ ^[0-9]+$ ]] || die "invalid GID_INDEX"
  F1_ADDRS=("$NODE0_F1" "$NODE1_F1" "$NODE2_F1" "$NODE3_F1")
  F0_ADDRS=("$NODE0_F0" "$NODE1_F0" "$NODE2_F0" "$NODE3_F0")
  local value
  for value in "${F1_ADDRS[@]}" "${F0_ADDRS[@]}"; do
    [[ "$value" =~ ^[0-9.]+$ ]] || die "unsafe fabric IP: $value"
  done
}

remote() {
  local host=${1:?host}; shift
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" "$@"
}

print_topology() {
  note "rank  management       port1 address   port0 address"
  local i
  for i in 0 1 2 3; do
    printf '%-5s %-16s %-15s %-15s\n' "$i" "${NODES[$i]}" "${F1_ADDRS[$i]}" "${F0_ADDRS[$i]}"
  done
  note "cables: node0:f1--node1:f1, node1:f0--node2:f0, node2:f1--node3:f1, node3:f0--node0:f0"
}
