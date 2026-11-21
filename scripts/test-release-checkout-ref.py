#!/usr/bin/env python3
"""Verify that Release resolves the version before checkout and checks out the normalized tag."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


def find_step(steps, marker):
    return next((step for step in steps if marker in step), None)


def extract_run(step):
    match = re.search(r"(?ms)^        run: \|\n(.*)", step)
    if match is None:
        raise AssertionError("run block not found")
    return textwrap.dedent(match.group(1))


class ReleaseCheckoutRefTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.steps = re.split(r"(?m)^      - ", WORKFLOW)[1:]
        cls.version_step = find_step(cls.steps, "id: version")
        cls.checkout = find_step(cls.steps, "uses: actions/checkout@")

    def run_version_step(self, event, version_input="", ref_name=""):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "output"
            output.touch()
            env = {
                "PATH": os.environ["PATH"],
                "GITHUB_EVENT_NAME": event,
                "GITHUB_REF_NAME": ref_name,
                "GITHUB_OUTPUT": str(output),
                "RELEASE_VERSION_INPUT": version_input,
            }
            result = subprocess.run(
                ["bash", "-c", extract_run(self.version_step)],
                env=env,
                capture_output=True,
                text=True,
            )
            outputs = dict(
                line.split("=", 1) for line in output.read_text().splitlines() if "=" in line
            )
            return result.returncode, outputs

    def test_version_step_runs_before_checkout(self):
        self.assertIsNotNone(self.version_step)
        self.assertIsNotNone(self.checkout)
        self.assertLess(
            self.steps.index(self.version_step),
            self.steps.index(self.checkout),
            "バージョン解決は checkout より前に行うこと",
        )

    def test_only_one_step_normalizes_version(self):
        normalizers = [step for step in self.steps if "RELEASE_VERSION_INPUT:" in step]
        self.assertEqual(len(normalizers), 1, "version の正規化は1ステップに集約すること")
        self.assertIn("RELEASE_VERSION_INPUT: ${{ github.event.inputs.version }}", self.version_step)

    def test_checkout_uses_resolved_tag_for_dispatch(self):
        match = re.search(r"(?m)^          ref: (.+?)[ \t]*$", self.checkout)
        self.assertIsNotNone(match, "checkout は ref を明示すること")
        self.assertIn("steps.version.outputs.tag", match.group(1))
        self.assertNotIn("github.event.inputs.version", self.checkout)

    def test_dispatch_normalizes_version_with_or_without_v_prefix(self):
        for raw in ("0.1.0", "v0.1.0"):
            with self.subTest(raw=raw):
                code, outputs = self.run_version_step("workflow_dispatch", version_input=raw)
                self.assertEqual(code, 0)
                self.assertEqual(outputs.get("tag"), "v0.1.0")
                self.assertEqual(outputs.get("version"), "0.1.0")

    def test_dispatch_rejects_empty_and_unsupported_input(self):
        for raw in ("", "0.1.0/x", "v"):
            with self.subTest(raw=raw):
                code, outputs = self.run_version_step("workflow_dispatch", version_input=raw)
                self.assertNotEqual(code, 0)
                self.assertNotIn("tag", outputs)

    def test_tag_push_uses_pushed_tag(self):
        code, outputs = self.run_version_step("push", ref_name="v1.2.3")
        self.assertEqual(code, 0)
        self.assertEqual(outputs.get("tag"), "v1.2.3")


if __name__ == "__main__":
    unittest.main()
