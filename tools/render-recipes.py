#!/usr/bin/env python3
"""Render canonical switchless and diagnostic switched eugr recipes."""
from __future__ import annotations

import argparse
import os
import pathlib
import re


def load_shell_values(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    assignment = re.compile(r"^([A-Z][A-Z0-9_]*)=(?:\"([^\"]*)\"|'([^']*)'|([^#\s]*))")
    for line in path.read_text().splitlines():
        match = assignment.match(line.strip())
        if match:
            values[match.group(1)] = next(v for v in match.groups()[1:] if v is not None)
    return values


def env_block(fabric: str, values: dict[str, str]) -> str:
    common = [
        f'  NCCL_SOCKET_IFNAME: "{values["MGMT_IF"]}"',
        f'  GLOO_SOCKET_IFNAME: "{values["MGMT_IF"]}"',
        '  NCCL_NET: "IB"',
        '  NCCL_IB_DISABLE: "0"',
        '  NCCL_CUMEM_ENABLE: "0"',
        '  NCCL_IGNORE_CPU_AFFINITY: "1"',
    ]
    if fabric == "switched":
        common += [
            f'  NCCL_IB_HCA: "{values["SWITCHED_HCA"]}"',
            f'  NCCL_IB_GID_INDEX: "{values.get("SWITCHED_GID_INDEX", "3")}"',
        ]
    else:
        common += [
            f'  NCCL_IB_HCA: "{values["F0_HCA"]},{values["F1_HCA"]}"',
            f'  NCCL_IB_GID_INDEX: "{values["GID_INDEX"]}"',
            '  NCCL_IB_SUBNET_PREFIX_LEN: "24"',
            '  NCCL_IB_SUBNET_AWARE_ROUTING: "1"',
            '  NCCL_ALGO: "Ring"',
            '  NCCL_MIN_NCHANNELS: "4"',
            '  NCCL_MAX_NCHANNELS: "4"',
            '  NCCL_CROSS_NIC: "1"',
            '  NCCL_SWITCHLESS_RING_ONLY: "1"',
            '  NCCL_SKIP_TREE_CONNECT: "1"',
            '  VLLM_NCCL_SO_PATH: "/opt/nccl-switchless/libnccl.so.2"',
            '  LD_PRELOAD: "/opt/nccl-switchless/libnccl.so.2"',
        ]
    return "\n".join(common)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--templates", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1] / "recipes")
    args = parser.parse_args()
    values = load_shell_values(args.config)
    required = {"MGMT_IF", "SWITCHED_HCA", "F0_HCA", "F1_HCA", "GID_INDEX", "ENGRAM_CONTAINER_ROOT"}
    missing = sorted(required - values.keys())
    if missing:
        raise SystemExit(f"missing config values: {', '.join(missing)}")
    values.setdefault("BASELINE_IMAGE", "vllm-dsv41-switchless-eugr:boot10")
    values.setdefault("B12X_IMAGE", "vllm-dsv41-switchless-eugr:b12x-candidate")
    values.setdefault("DSV41_ALLOW_UNQUALIFIED_B12X", "NO")
    args.out.mkdir(parents=True, exist_ok=True)
    for template in sorted(args.templates.glob("*.yaml.in")):
        raw = template.read_text()
        for fabric in ("switchless", "switched"):
            # Switchless is the defining path and therefore owns the canonical
            # recipe name. The conventional fabric is retained only as an
            # explicitly named diagnostic fallback.
            suffix = "" if fabric == "switchless" else "-switched"
            rendered = raw.replace("__FABRIC_SUFFIX__", suffix)
            rendered = rendered.replace("__FABRIC_NAME__", fabric.title())
            rendered = rendered.replace("__FABRIC_ENV__", env_block(fabric, values))
            rendered = rendered.replace("__BASELINE_IMAGE__", values["BASELINE_IMAGE"])
            rendered = rendered.replace("__B12X_IMAGE__", values["B12X_IMAGE"])
            rendered = rendered.replace("__MODEL_REVISION__", "dba1be0a40aa45a94ad051997016db3960a90277")
            rendered = rendered.replace("__B12X_OPT_IN__", values["DSV41_ALLOW_UNQUALIFIED_B12X"])
            rendered = rendered.replace("__ENGRAM_DIR__", values["ENGRAM_CONTAINER_ROOT"])
            target = args.out / (template.name.removesuffix(".yaml.in") + suffix + ".yaml")
            target.write_text(rendered)
            print(f"rendered {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
