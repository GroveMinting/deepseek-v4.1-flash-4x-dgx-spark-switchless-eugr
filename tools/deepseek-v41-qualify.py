#!/usr/bin/env python3
"""OpenAI-compatible text, tool, vision and token-sequence qualification."""
from __future__ import annotations

import argparse
import base64
import json
import pathlib
import time
import urllib.error
import urllib.request

PNG = base64.b64encode(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6l9sAAAAASUVORK5CYII="
)).decode()


def request(base: str, path: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base.rstrip("/") + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as response:
        return json.load(response)


def completion(base: str, model: str, messages: list[dict], **extra) -> dict:
    body = {"model": model, "messages": messages, "temperature": 0, "max_tokens": 64,
            "stream": False, "chat_template_kwargs": {"thinking": False}, **extra}
    return request(base, "/v1/chat/completions", body)


def token_sequence(response: dict) -> list[str]:
    content = response.get("choices", [{}])[0].get("logprobs", {}).get("content") or []
    return [item.get("token", "") for item in content]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="http://127.0.0.1:8000")
    p.add_argument("--model", default="deepseek-v4.1-flash")
    p.add_argument("--receipt", type=pathlib.Path)
    p.add_argument("--reference", type=pathlib.Path)
    p.add_argument("--write-reference", type=pathlib.Path)
    p.add_argument("--require-dspark-metrics", action="store_true")
    args = p.parse_args()
    checks: dict[str, object] = {}
    started = time.time()
    try:
        models = request(args.base, "/v1/models")
        checks["models"] = bool(models.get("data"))

        literal = completion(args.base, args.model,
                             [{"role": "user", "content": "Reply with exactly SPARK_V41_OK"}],
                             logprobs=True)
        text = literal["choices"][0]["message"].get("content", "")
        checks["text"] = "SPARK_V41_OK" in text
        checks["text_tokens"] = token_sequence(literal)

        tools = [{"type": "function", "function": {"name": "spark_temperature",
                  "description": "Return a Spark temperature", "parameters": {"type": "object",
                  "properties": {"rank": {"type": "integer"}}, "required": ["rank"]}}}]
        tool_resp = completion(args.base, args.model,
                               [{"role": "user", "content": "Call spark_temperature for rank 2."}],
                               tools=tools, tool_choice="required")
        calls = tool_resp["choices"][0]["message"].get("tool_calls") or []
        checks["tool_call"] = bool(calls and calls[0].get("function", {}).get("name") == "spark_temperature")

        vision = completion(args.base, args.model, [{"role": "user", "content": [
            {"type": "text", "text": "State whether this image loaded; answer IMAGE_OK."},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{PNG}"}},
        ]}])
        checks["vision"] = bool(vision["choices"][0]["message"].get("content", "").strip())

        if args.reference:
            reference = json.loads(args.reference.read_text())
            expected = reference.get("text_tokens")
            checks["reference_token_sequence"] = bool(expected and expected == checks["text_tokens"])
        if args.write_reference:
            args.write_reference.parent.mkdir(parents=True, exist_ok=True)
            args.write_reference.write_text(json.dumps({
                "model": args.model, "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "text_tokens": checks["text_tokens"],
            }, indent=2) + "\n")

        if args.require_dspark_metrics:
            with urllib.request.urlopen(args.base.rstrip("/") + "/metrics", timeout=30) as response:
                metrics = response.read().decode(errors="replace").lower()
            checks["dspark_metrics"] = "speculat" in metrics and ("accept" in metrics or "draft" in metrics)
    except (KeyError, ValueError, urllib.error.URLError, TimeoutError) as exc:
        checks["exception"] = repr(exc)

    passed = all(value is True or isinstance(value, list) for key, value in checks.items()
                 if key != "exception") and "exception" not in checks
    receipt = {"status": "PASS" if passed else "FAIL", "elapsed_seconds": time.time() - started,
               "base": args.base, "model": args.model, "checks": checks}
    print(json.dumps(receipt, indent=2))
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
