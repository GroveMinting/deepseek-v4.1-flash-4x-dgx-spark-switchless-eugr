from __future__ import annotations

import pathlib
import re
import subprocess
import tempfile
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def render(self, config: pathlib.Path, out: pathlib.Path) -> list[pathlib.Path]:
        subprocess.run(["python3", str(ROOT / "tools/render-recipes.py"),
                        "--config", str(config), "--out", str(out)], check=True,
                       capture_output=True, text=True)
        return sorted(out.glob("*.yaml"))

    def test_lock_uses_full_immutable_commits(self) -> None:
        text = (ROOT / "VERSIONS.lock").read_text()
        for key in ("EUGR_COMMIT", "MODEL_REVISION", "VLLM_COMMIT", "FLASHINFER_COMMIT",
                    "CUTLASS_COMMIT", "CCCL_COMMIT", "SPDLOG_COMMIT"):
            match = re.search(rf'^{key}="([0-9a-f]+)"$', text, re.M)
            self.assertIsNotNone(match, key)
            self.assertEqual(len(match.group(1)), 40, key)

    def test_recipe_matrix_and_invariants(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.render(ROOT / "config/cluster.env.example", pathlib.Path(directory))
            self.assertEqual(len(paths), 16)
            for path in paths:
                data = yaml.safe_load(path.read_text())
                self.assertEqual(data["defaults"]["tensor_parallel"], 4)
                self.assertEqual(data["defaults"]["max_num_seqs"], 1)
                self.assertIn("dba1be0a40aa45a94ad051997016db3960a90277", data["command"])
                command = data["command"].format(**data["defaults"])
                self.assertIn("--tensor-parallel-size 4", command)
                self.assertNotIn("{{", command)
                if path.stem.endswith("-switched"):
                    self.assertNotIn("LD_PRELOAD", data["env"])
                    self.assertNotIn("NCCL_SWITCHLESS_RING_ONLY", data["env"])
                else:
                    self.assertEqual(data["env"]["NCCL_SWITCHLESS_RING_ONLY"], "1")
                    self.assertEqual(data["env"]["NCCL_ALGO"], "Ring")
                    self.assertIn("LD_PRELOAD", data["env"])
                if "b12x" in path.name:
                    self.assertEqual(data["env"]["DSV41_ALLOW_UNQUALIFIED_B12X"], "NO")

    def test_graph_capture_set_is_exact(self) -> None:
        expected = "[5,6,10,12,15,18,20,24,25,30,35,36,40,42,48]"
        for path in (ROOT / "recipes").glob("*graphs*.in"):
            self.assertIn(expected, path.read_text())
        for path in (ROOT / "recipes").glob("*dspark*.in"):
            self.assertIn(expected, path.read_text())

    def test_switchless_project_identity(self) -> None:
        wrapper = (ROOT / "run-deepseek-v41.sh").read_text()
        versions = (ROOT / "VERSIONS.lock").read_text()
        dockerfiles = (
            (ROOT / "runtime" / "Dockerfile.runtime").read_text()
            + (ROOT / "runtime" / "Dockerfile.b12x").read_text()
        )
        self.assertIn("FABRIC=switchless", wrapper)
        self.assertIn("vllm-dsv41-switchless-eugr:boot10", versions)
        self.assertIn("deepseek-v4.1-flash-4x-dgx-spark-switchless-eugr", dockerfiles)
        docs = {path.name for path in (ROOT / "docs").glob("*.md")}
        self.assertEqual(docs, {"ACTIVATION.md", "B12X-READINESS.md", "NETWORKING.md"})

    def test_b12x_promotion_requires_switchless_receipt(self) -> None:
        qualification = (ROOT / "tools" / "deepseek-v41-qualify.sh").read_text()
        wrapper = (ROOT / "run-deepseek-v41.sh").read_text()
        gate = (ROOT / "switchless" / "nccl-gate.sh").read_text()
        self.assertIn(".receipts/switchless-nccl.env", qualification)
        self.assertIn("NCCL_LIBRARY_SHA256", qualification)
        self.assertIn("receipt_fabric", wrapper)
        self.assertIn(".receipts/switchless-nccl.env", gate)

    def test_wrapper_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            eugr = work / "eugr"
            eugr.mkdir()
            runner = eugr / "run-recipe.sh"
            runner.write_text("#!/usr/bin/env bash\nexit 0\n")
            runner.chmod(0o755)
            config = work / "cluster.env"
            source = (ROOT / "config/cluster.env.example").read_text()
            source = re.sub(r'^EUGR_DIR=.*$', f'EUGR_DIR="{eugr}"', source, flags=re.M)
            config.write_text(source)
            result = subprocess.run([str(ROOT / "run-deepseek-v41.sh"), "--config", str(config),
                                     "--runtime", "baseline", "--profile", "dspark",
                                     "--dry-run", "-d"],
                                    check=True, capture_output=True, text=True)
            self.assertIn("deepseek-v41-baseline-dspark", result.stdout)
            self.assertNotIn("deepseek-v41-baseline-dspark-switched", result.stdout)
            self.assertIn("--no-ray", result.stdout)

    def test_switched_fallback_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            eugr = work / "eugr"
            eugr.mkdir()
            runner = eugr / "run-recipe.sh"
            runner.write_text("#!/usr/bin/env bash\nexit 0\n")
            runner.chmod(0o755)
            config = work / "cluster.env"
            source = (ROOT / "config/cluster.env.example").read_text()
            source = re.sub(r'^EUGR_DIR=.*$', f'EUGR_DIR="{eugr}"', source, flags=re.M)
            config.write_text(source)
            result = subprocess.run([str(ROOT / "run-deepseek-v41.sh"), "--config", str(config),
                                     "--runtime", "baseline", "--fabric", "switched",
                                     "--profile", "base", "--dry-run"],
                                    check=True, capture_output=True, text=True)
            self.assertIn("deepseek-v41-baseline-base-switched", result.stdout)


if __name__ == "__main__":
    unittest.main()
