#!/usr/bin/env python3
"""共有テストランナーと CI / Release の呼出しを xcodebuild スタブで検証する。"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
DOWNLOAD = "-skip-testing:LocalTranscriberTests/ModelDownloadIntegrationTests"
LOAD = "-skip-testing:LocalTranscriberTests/ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder"
UI = "-skip-testing:LocalTranscriberUITests"
DEFAULTS = {
    "PROJECT": "LocalTranscriber.xcodeproj",
    "SCHEME": "LocalTranscriber",
    "DERIVED_DATA_PATH": "DerivedData",
}


def workflow_test_command(mode):
    workflow = (ROOT / f".github/workflows/{mode}.yml").read_text(encoding="utf-8")
    match = re.search(
        r"^      - name: Run tests\n        run: \|\n((?:          [^\n]*\n?)+)",
        workflow,
        flags=re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"{mode}: Run tests step not found")
    return textwrap.dedent(match[1])


class RunTestsScriptTests(unittest.TestCase):
    def run_script(
        self,
        args,
        overrides=None,
        exit_code=0,
        command=None,
        summary_data=None,
    ):
        with tempfile.TemporaryDirectory(prefix="run tests ") as directory:
            work = Path(directory)
            log = work / "invocations.jsonl"
            stub = work / "tool-stub.py"
            stub.write_text(
                "import json, os, pathlib, sys\n"
                "tool = sys.argv[1]\n"
                "args = sys.argv[2:]\n"
                "if tool == 'xcodebuild':\n"
                "    with open(os.environ['XCODEBUILD_LOG'], 'a', encoding='utf-8') as log:\n"
                "        log.write(json.dumps(args) + '\\n')\n"
                "    if '-resultBundlePath' in args:\n"
                "        bundle = pathlib.Path(args[args.index('-resultBundlePath') + 1])\n"
                "        bundle.mkdir(parents=True, exist_ok=True)\n"
                "    sys.exit(int(os.environ['XCODEBUILD_EXIT_CODE']))\n"
                "elif tool == 'xcrun':\n"
                "    assert args[:4] == ['xcresulttool', 'get', 'test-results', 'summary'], args\n"
                "    print(os.environ['XCRESULT_SUMMARY'])\n"
                "    sys.exit(0)\n"
                "sys.exit(2)\n",
                encoding="utf-8",
            )
            default_summary = {
                "totalTestCount": 10,
                "devicesAndConfigurations": [
                    {"passedTests": 9, "failedTests": 0, "expectedFailures": 0, "skippedTests": 1}
                ],
            }
            env = dict(os.environ)
            for key in (*DEFAULTS, "RESULT_ROOT"):
                env.pop(key, None)
            env.update({
                "RESULT_ROOT": str(work / "results"),
                "TOOL_STUB": str(stub),
                "XCODEBUILD_LOG": str(log),
                "XCODEBUILD_EXIT_CODE": str(exit_code),
                "XCRESULT_SUMMARY": json.dumps(summary_data if summary_data is not None else default_summary),
            })
            env.update(overrides or {})
            # Nightly の回帰テストと同様、実行権限不要の shell 関数で差し替える。
            wrappers = '''
xcodebuild() { python3 "$TOOL_STUB" xcodebuild "$@"; }
xcrun() { python3 "$TOOL_STUB" xcrun "$@"; }
export -f xcodebuild xcrun
'''
            argv = ["bash", "-e", "-o", "pipefail", "-c", wrappers + (command or 'bash "$@"'),
                    "test-run-tests", str(ROOT / "scripts/run-tests.sh"), *args]
            result = subprocess.run(
                argv, cwd=ROOT, env=env, capture_output=True, text=True, timeout=10,
            )
            invocations = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, invocations

    def assert_invocation(self, invocations, mode, settings=None):
        settings = settings or DEFAULTS
        self.assertEqual(len(invocations), 1)
        args = invocations[0]
        self.assertEqual(args[:10], [
            "test", "-project", settings["PROJECT"],
            "-scheme", settings["SCHEME"], "-destination", "platform=macOS",
            "CODE_SIGNING_ALLOWED=NO", "-derivedDataPath", settings["DERIVED_DATA_PATH"],
        ])
        self.assertEqual(args[10], "-resultBundlePath")
        self.assertTrue(args[11].endswith(f"/{mode}Tests.xcresult"), args[11])
        # 完全一致で余分な除外や only-testing の混入も検出する。
        self.assertCountEqual(args[12:], [DOWNLOAD, LOAD, UI] if mode == "ci" else [DOWNLOAD, LOAD])

    def test_modes_preserve_existing_test_selection(self):
        for mode in ("ci", "release"):
            with self.subTest(mode=mode):
                result, invocations = self.run_script([mode])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_invocation(invocations, mode)

    def test_existing_release_settings_remain_single_arguments(self):
        settings = {
            "PROJECT": "Project with spaces.xcodeproj",
            "SCHEME": "Scheme with spaces",
            "DERIVED_DATA_PATH": "Build output/DerivedData",
        }
        for mode in ("ci", "release"):
            with self.subTest(mode=mode):
                result, invocations = self.run_script([mode], overrides=settings)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_invocation(invocations, mode, settings)

    def test_invalid_arguments_do_not_invoke_xcodebuild(self):
        for args in ([], ["unknown"], ["nightly"], ["ci", "release"], [""]):
            with self.subTest(args=args):
                result, invocations = self.run_script(args)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("Usage:", result.stderr)
                self.assertEqual(invocations, [])

    def test_xcodebuild_failure_is_propagated(self):
        for mode in ("ci", "release"):
            with self.subTest(mode=mode):
                result, invocations = self.run_script([mode], exit_code=65)
                self.assertEqual(result.returncode, 65, result.stderr)
                self.assert_invocation(invocations, mode)

    def test_workflows_delegate_to_the_matching_mode(self):
        for mode in ("ci", "release"):
            with self.subTest(mode=mode):
                command = workflow_test_command(mode)
                self.assertEqual(command.strip(), f"bash scripts/run-tests.sh {mode}")
                result, invocations = self.run_script([], command=command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_invocation(invocations, mode)

    def test_zero_total_or_all_skipped_results_fail(self):
        cases = [
            ("zero_total", {"totalTestCount": 0, "devicesAndConfigurations": []}),
            (
                "all_skipped",
                {
                    "totalTestCount": 5,
                    "devicesAndConfigurations": [
                        {"passedTests": 0, "failedTests": 0, "expectedFailures": 0, "skippedTests": 5}
                    ],
                },
            ),
        ]
        for label, summary in cases:
            with self.subTest(case=label):
                result, _ = self.run_script(["ci"], summary_data=summary)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("executed 0 tests", result.stderr)


if __name__ == "__main__":
    unittest.main()
