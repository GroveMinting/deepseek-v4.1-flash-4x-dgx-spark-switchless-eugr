#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
CONFIG="$ROOT/config/cluster.env"
[[ ${1:-} != --config ]] || { CONFIG=${2:?missing config path}; shift 2; }
(($# == 0)) || die "usage: $0 [--config FILE]"
load_config "$CONFIG"
require_switchless_config

for i in 0 1 2 3; do
  host=${NODES[$i]}; f1=${F1_ADDRS[$i]}; f0=${F0_ADDRS[$i]}
  remote "$host" "set -eu
    check() {
      hca=\$1 dev=\$2 expected=\$3
      base=/sys/class/infiniband/\$hca/ports/1
      state=\$(cat \"\$base/state\")
      type=\$(cat \"\$base/gid_attrs/types/$GID_INDEX\")
      gid=\$(cat \"\$base/gids/$GID_INDEX\")
      ndev=\$(cat \"\$base/gid_attrs/ndevs/$GID_INDEX\")
      mtu=\$(cat /sys/class/net/\$dev/mtu)
      addr=\$(ip -4 -o address show dev \"\$dev\" | awk '{print \$4}')
      test \"\$state\" = '4: ACTIVE' || { echo \"\$hca not ACTIVE: \$state\" >&2; exit 1; }
      test \"\$type\" = 'RoCE v2' || { echo \"\$hca GID $GID_INDEX is \$type\" >&2; exit 1; }
      test \"\$gid\" != 0000:0000:0000:0000:0000:0000:0000:0000 || { echo \"\$hca GID empty\" >&2; exit 1; }
      test \"\$ndev\" = \"\$dev\" || { echo \"\$hca maps to \$ndev, expected \$dev\" >&2; exit 1; }
      test \"\$mtu\" = 9000 || { echo \"\$dev MTU=\$mtu\" >&2; exit 1; }
      test \"\$addr\" = \"\$expected/24\" || { echo \"\$dev address=\$addr\" >&2; exit 1; }
    }
    check $F1_HCA $F1_IF $f1
    check $F0_HCA $F0_IF $f0
    echo \" \$(hostname): both RoCE v2 rails active, mapped, addressed, MTU 9000\""
done

# One jumbo packet test per physical edge, both directions would be redundant here.
remote "${NODES[0]}" "ping -q -M do -s 8972 -c 2 -W 2 ${F1_ADDRS[1]} >/dev/null"
remote "${NODES[1]}" "ping -q -M do -s 8972 -c 2 -W 2 ${F0_ADDRS[2]} >/dev/null"
remote "${NODES[2]}" "ping -q -M do -s 8972 -c 2 -W 2 ${F1_ADDRS[3]} >/dev/null"
remote "${NODES[3]}" "ping -q -M do -s 8972 -c 2 -W 2 ${F0_ADDRS[0]} >/dev/null"
note "fabric verification passed: 4 ranks, 8 rails/GIDs/MTUs, 4 jumbo edges"
note "Next proof: run switchless/nccl-gate.sh. Ping alone is not sufficient."
