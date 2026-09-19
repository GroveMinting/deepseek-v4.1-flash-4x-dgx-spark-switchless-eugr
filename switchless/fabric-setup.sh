#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"

CONFIG="$ROOT/config/cluster.env"
APPLY=0
while (($#)); do
  case "$1" in
    --config) CONFIG=${2:?missing config path}; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) echo "usage: $0 [--config FILE] [--apply]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
load_config "$CONFIG"
require_switchless_config

print_topology
note ""
note "Planned per-node changes: unmanage $F0_IF/$F1_IF, flush their addresses,"
note "set MTU 9000, assign the listed /24s, enable IPv4 forwarding, and add"
note "DOCKER-USER ACCEPT rules only for those two fabric interfaces."

if ((APPLY == 0)); then
  note "DRY RUN ONLY. Re-run with --apply after reviewing config and cabling."
  exit 0
fi
[[ ${I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES:-NO} == YES ]] || \
  die "set I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES=YES after reviewing the dry run"

note "Preflight: all ranks must be reachable, rails present, and GPUs idle."
for host in "${NODES[@]}"; do
  remote "$host" "set -eu
    test -e /sys/class/net/$F1_IF
    test -e /sys/class/net/$F0_IF
    test -d /sys/class/infiniband/$F1_HCA
    test -d /sys/class/infiniband/$F0_HCA
    pids=\$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null || true)
    test -z \"\$pids\" || { echo 'GPU compute active; stop all GPU workloads first' >&2; exit 1; }
    echo \" \$(hostname): ready\""
done

for i in 0 1 2 3; do
  host=${NODES[$i]}; f1=${F1_ADDRS[$i]}; f0=${F0_ADDRS[$i]}
  remote "$host" "set -eu
    sudo nmcli device set $F1_IF managed no 2>/dev/null || true
    sudo nmcli device set $F0_IF managed no 2>/dev/null || true
    sudo ip addr flush dev $F1_IF
    sudo ip addr flush dev $F0_IF
    sudo ip link set $F1_IF mtu 9000 up
    sudo ip link set $F0_IF mtu 9000 up
    sudo ip addr add $f1/24 dev $F1_IF
    sudo ip addr add $f0/24 dev $F0_IF
    sudo sysctl -qw net.ipv4.ip_forward=1
    if sudo iptables -S DOCKER-USER >/dev/null 2>&1; then
      sudo iptables -C DOCKER-USER -i $F1_IF -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i $F1_IF -j ACCEPT
      sudo iptables -C DOCKER-USER -o $F1_IF -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -o $F1_IF -j ACCEPT
      sudo iptables -C DOCKER-USER -i $F0_IF -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i $F0_IF -j ACCEPT
      sudo iptables -C DOCKER-USER -o $F0_IF -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -o $F0_IF -j ACCEPT
    fi
    echo \" \$(hostname): $F1_IF=$f1/24 $F0_IF=$f0/24 MTU=9000\""
done

exec "$ROOT/switchless/fabric-verify.sh" --config "$CONFIG"
