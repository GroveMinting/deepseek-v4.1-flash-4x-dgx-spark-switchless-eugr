#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "$ROOT/runtime/common.sh"
load_versions
CONFIG=${1:-$ROOT/config/cluster.env}
IMAGE=${2:-${IMAGE:-$BASELINE_IMAGE}}
load_config "$CONFIG"
docker image inspect "$IMAGE" >/dev/null || die "local image not found: $IMAGE"
expected=$(docker image inspect --format '{{.Id}}' "$IMAGE")
archive=$(mktemp --suffix=.tar.gz)
trap 'rm -f "$archive"' EXIT
note "exporting $IMAGE ($expected)"
docker save "$IMAGE" | gzip -1 > "$archive"
for host in "${NODES[@]}"; do
  note "loading $IMAGE on $host"
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" docker load < "$archive"
  actual=$(remote "$host" "docker image inspect --format '{{.Id}}' '$IMAGE'")
  [[ "$actual" == "$expected" ]] || die "image digest mismatch on $host: $actual"
done
note "image parity passed on all four ranks: $expected"
