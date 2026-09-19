#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../runtime/common.sh
source "$ROOT/runtime/common.sh"
load_versions
DEST="$ROOT/build/nccl-switchless"
while (($#)); do
  case "$1" in
    --dest) DEST=${2:?missing destination}; shift 2 ;;
    -h|--help) echo "usage: $0 [--dest DIR]"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
mkdir -p "$ROOT/build/downloads" "$DEST"
archive="$ROOT/build/downloads/$SWITCHLESS_NCCL_ARCHIVE"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --output "$archive.part" "$SWITCHLESS_NCCL_URL"
  mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$SWITCHLESS_NCCL_ARCHIVE_SHA256" "$archive" | sha256sum -c -
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$archive" -C "$tmp"
lib=$(find -L "$tmp" -type f \( -name 'libnccl.so.2' -o -name 'libnccl.so.2.30.7' \) -print -quit)
[[ -n "$lib" ]] || die "release archive did not contain libnccl.so.2"
actual=$(sha256sum "$lib" | awk '{print $1}')
[[ "$actual" == "$SWITCHLESS_NCCL_LIBRARY_SHA256" ]] || die "NCCL library hash mismatch: $actual"
install -m 0755 "$lib" "$DEST/libnccl.so.2"
printf '%s  libnccl.so.2\n' "$actual" > "$DEST/SHA256SUMS"
note "installed verified switchless NCCL $SWITCHLESS_NCCL_VERSION at $DEST"
