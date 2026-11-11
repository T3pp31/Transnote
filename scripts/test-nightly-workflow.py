#!/usr/bin/env python3
"""Run nightly's model-test shell steps with local xcodebuild/xcresulttool stubs."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
DOWNLOAD = "LocalTranscriberTests/ModelDownloadIntegrationTests"
LOAD = "LocalTranscriberTests/ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder"


def model_test_steps():
    # Exercise the workflow itself, rather than duplicating its validation logic.
    workflow = (ROOT / ".github/workflows/nightly.yml").read_text(encoding="utf-8")
    steps = re.split(r"^      - name: ", workflow, flags=re.MULTILINE)
    scripts = []
    for step in steps:
        if step.splitlines()[0] not in (
            "Run real-model tests (normally skipped)",
            "Verify real-model tests executed",
        ):
            continue
        script = step.split("        run: |\n", 1)[1]
        scripts.append(textwrap.dedent(script))
    if not scripts:
        raise AssertionError("nightly model-test steps not found")
    return "\n".join(scripts)


STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

tool = sys.argv[1]
args = sys.argv[2:]
if tool == "xcodebuild":
    assert args[0] == "test", args
    assert os.environ["RUN_MODEL_INTEGRATION_TESTS"] == "1"
    with open("invocations.jsonl", "a", encoding="utf-8") as log:
        log.write(json.dumps(args) + "\n")
    if os.environ.get("TOOL_FAILURE") == "xcodebuild":
        sys.exit(65)
    selectors = [arg.split(":", 1)[1] for arg in args if arg.startswith("-only-testing:")]
    assert selectors, args
    total = passed = expected = 0
    for selector in selectors:
        assert selector in json.loads(os.environ["TEST_SELECTORS"]), selector
        count = 2 if selector.endswith("ModelDownloadIntegrationTests") else 1
        mode = json.loads(os.environ["TEST_MODES"]).get(selector, "passed")
        if mode == "missing":
            continue
        total += count
        if mode == "passed":
            passed += count
        elif mode == "expectedFailure":
            expected += count
    bundle = Path(args[args.index("-resultBundlePath") + 1])
    bundle.mkdir(parents=True)
    summary = {
        "totalTestCount": total,
        "devicesAndConfigurations": [{
            "passedTests": passed, "failedTests": 0, "expectedFailures": expected,
        }],
    }
    (bundle / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
else:
    assert args[:4] == ["xcresulttool", "get", "test-results", "summary"], args
    assert "--compact" in args, args
    if os.environ.get("TOOL_FAILURE") == "xcresulttool":
        sys.exit(1)
    if os.environ.get("TOOL_FAILURE") == "invalid-json":
        print("not JSON")
    else:
        bundle = Path(args[args.index("--path") + 1])
        print((bundle / "summary.json").read_text(encoding="utf-8"))
'''


class NightlyWorkflowTests(unittest.TestCase):
    def run_workflow(self, modes=None, tool_failure=""):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            stub = work / "tool-stub.py"
            stub.write_text(STUB, encoding="utf-8")
            env = {
                **os.environ,
                "TOOL_STUB": str(stub),
                "RUN_MODEL_INTEGRATION_TESTS": "1",
                "TEST_SELECTORS": json.dumps([DOWNLOAD, LOAD]),
                "TEST_MODES": json.dumps(modes or {}),
                "TOOL_FAILURE": tool_failure,
            }
            wrappers = '''
xcodebuild() { python3 "$TOOL_STUB" xcodebuild "$@"; }
xcrun() { python3 "$TOOL_STUB" xcrun "$@"; }
'''
            result = subprocess.run(
                ["bash", "-e", "-o", "pipefail", "-c", wrappers + model_test_steps()],
                cwd=work, env=env, capture_output=True, text=True, timeout=30,
            )
            log = work / "invocations.jsonl"
            invocations = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, invocations

    def test_both_selectors_execute_in_separate_bundles(self):
        result, invocations = self.run_workflow()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(invocations), 2)
        self.assertEqual(
            [[arg for arg in args if arg.startswith("-only-testing:")] for args in invocations],
            [[f"-only-testing:{DOWNLOAD}"], [f"-only-testing:{LOAD}"]],
        )
        bundles = [args[args.index("-resultBundlePath") + 1] for args in invocations]
        self.assertEqual(len(set(bundles)), 2)

    def test_either_missing_selector_fails_even_when_the_other_can_pass(self):
        for selector in (DOWNLOAD, LOAD):
            with self.subTest(selector=selector):
                result, _ = self.run_workflow({selector: "missing"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("FAIL:", result.stderr)
                self.assertIn(selector, result.stderr)

    def test_either_fully_skipped_selector_fails(self):
        for selector in (DOWNLOAD, LOAD):
            with self.subTest(selector=selector):
                result, _ = self.run_workflow({selector: "skipped"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("FAIL:", result.stderr)
                self.assertIn(selector, result.stderr)

    def test_all_missing_fails(self):
        result, _ = self.run_workflow({DOWNLOAD: "missing", LOAD: "missing"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("FAIL:", result.stderr)

    def test_expected_failures_still_count_as_executed(self):
        result, _ = self.run_workflow({DOWNLOAD: "expectedFailure", LOAD: "expectedFailure"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tool_and_json_errors_are_not_hidden(self):
        for failure in ("xcodebuild", "xcresulttool", "invalid-json"):
            with self.subTest(failure=failure):
                result, _ = self.run_workflow(tool_failure=failure)
                self.assertNotEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
