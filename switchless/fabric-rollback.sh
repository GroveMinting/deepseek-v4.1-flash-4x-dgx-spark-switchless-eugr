#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
CONFIG="$ROOT/config/cluster.env"; APPLY=0
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config}; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) die "usage: $0 [--config FILE] [--apply]" ;;
  esac
done
load_config "$CONFIG"
require_switchless_config
note "Rollback removes only this package's configured fabric addresses and"
note "DOCKER-USER rules, then returns both rails to NetworkManager control."
((APPLY)) || { note "DRY RUN ONLY. Add --apply to proceed."; exit 0; }
[[ ${I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES:-NO} == YES ]] || die "confirmation token is not YES"
for i in 0 1 2 3; do
  host=${NODES[$i]}; f1=${F1_ADDRS[$i]}; f0=${F0_ADDRS[$i]}
  remote "$host" "set -eu
    sudo ip addr del $f1/24 dev $F1_IF 2>/dev/null || true
    sudo ip addr del $f0/24 dev $F0_IF 2>/dev/null || true
    if sudo iptables -S DOCKER-USER >/dev/null 2>&1; then
      sudo iptables -D DOCKER-USER -i $F1_IF -j ACCEPT 2>/dev/null || true
      sudo iptables -D DOCKER-USER -o $F1_IF -j ACCEPT 2>/dev/null || true
      sudo iptables -D DOCKER-USER -i $F0_IF -j ACCEPT 2>/dev/null || true
      sudo iptables -D DOCKER-USER -o $F0_IF -j ACCEPT 2>/dev/null || true
    fi
    sudo nmcli device set $F1_IF managed yes 2>/dev/null || true
    sudo nmcli device set $F0_IF managed yes 2>/dev/null || true
    echo \" \$(hostname): package fabric settings removed\""
done
