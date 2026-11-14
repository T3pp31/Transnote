#!/usr/bin/env python3
"""Check the shared Xcode config and execute each workflow's read step locally."""

import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
REFERENCE = "${{ steps.xcode_config.outputs.version }}"


class XcodeVersionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.project = self.work / "project with spaces"
        (self.project / "scripts").mkdir(parents=True)
        (self.project / "Config").mkdir()
        self.reader = self.project / "scripts/read-xcode-version.py"
        self.config = self.project / "Config/toolchain.plist"
        shutil.copyfile(ROOT / "scripts/read-xcode-version.py", self.reader)
        shutil.copyfile(ROOT / "Config/toolchain.plist", self.config)

    def write_config(self, data):
        self.config.write_bytes(plistlib.dumps(data))

    def read_version(self):
        # Resolve config relative to the script, not the caller's working directory.
        return subprocess.run(
            [sys.executable, str(self.reader)], cwd=self.work,
            capture_output=True, text=True, check=False, timeout=10,
        )

    def read_step(self, workflow_name):
        workflow = (ROOT / f".github/workflows/{workflow_name}.yml").read_text(encoding="utf-8")
        steps = re.split(r"^      - ", workflow, flags=re.MULTILINE)[1:]
        indexes = [i for i, step in enumerate(steps) if step.startswith("name: Read Xcode version\n")]
        self.assertEqual(len(indexes), 1, workflow_name)
        index = indexes[0]
        step = steps[index]
        self.assertIn("        id: xcode_config\n", step)
        checkout = next(i for i, item in enumerate(steps) if "uses: actions/checkout@" in item)
        setup = next(i for i, item in enumerate(steps) if "uses: maxim-lobanov/setup-xcode@" in item)
        self.assertLess(checkout, index)
        self.assertLess(index, setup)
        self.assertIn(f"          xcode-version: {REFERENCE}\n", steps[setup])
        self.assertNotIn("XCODE_VERSION", workflow)
        cache_lines = [line for line in workflow.splitlines() if "-${{ runner.os }}-xcode-" in line]
        self.assertEqual(len(cache_lines), {"ci": 3, "release": 0, "nightly": 1}[workflow_name])
        for line in cache_lines:
            self.assertIn(f"-xcode-{REFERENCE}-", line)
        return textwrap.dedent(step.split("        run: |\n", 1)[1])

    def run_step(self, script):
        output = self.work / "github-output"
        output.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", script], cwd=self.project,
            env={**os.environ, "GITHUB_OUTPUT": str(output)},
            capture_output=True, text=True, check=False, timeout=10,
        )
        return result, output.read_text(encoding="utf-8") if output.exists() else ""

    def test_repository_config_and_patch_version_from_another_directory(self):
        expected = plistlib.loads(self.config.read_bytes())["XcodeVersion"]
        for version in (expected, "99.1.2"):
            with self.subTest(version=version):
                self.write_config({"XcodeVersion": version})
                result = self.read_version()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, version + "\n")
                self.assertEqual(result.stderr, "")

    def test_invalid_values_emit_no_version(self):
        for value in (None, "", "latest", "16", "16.4\nother=value", " 16.4", 16.4, True, []):
            with self.subTest(value=value):
                self.write_config({"XcodeVersion": value} if value is not None else {})
                result = self.read_version()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("Invalid XcodeVersion", result.stderr)
        self.write_config(["not a dictionary"])
        result = self.read_version()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("Invalid XcodeVersion", result.stderr)

    def test_missing_or_malformed_config_fails(self):
        for content in (None, b"not a plist", b"<?xml version='1.0'?><plist><dict>"):
            with self.subTest(content=content):
                self.config.unlink(missing_ok=True)
                if content is not None:
                    self.config.write_bytes(content)
                result = self.read_version()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("Failed to read", result.stderr)

    def test_all_workflows_follow_config_changes(self):
        expected = plistlib.loads(self.config.read_bytes())["XcodeVersion"]
        for workflow in ("ci", "release", "nightly"):
            script = self.read_step(workflow)
            for version in (expected, "99.1.2"):
                with self.subTest(workflow=workflow, version=version):
                    self.write_config({"XcodeVersion": version})
                    result, output = self.run_step(script)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(output, f"version={version}\n")

    def test_all_workflows_stop_without_output_on_bad_config(self):
        for workflow in ("ci", "release", "nightly"):
            with self.subTest(workflow=workflow):
                self.write_config({"XcodeVersion": ""})
                result, output = self.run_step(self.read_step(workflow))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output, "")
                self.assertIn("Invalid XcodeVersion", result.stderr)


if __name__ == "__main__":
    unittest.main()
