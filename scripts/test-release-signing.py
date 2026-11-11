#!/usr/bin/env python3
"""Release workflow signing regression tests without macOS or real credentials."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent

MOCKS = """
security() {
  local command="$1"
  printf '%s\\n' "$command" >> "$MOCK_LOG"
  if [[ "$command" == set-key-partition-list ]]; then
    shift
    [[ $# -eq 6 && "$1" == -S && "$2" == apple-tool:,apple:,codesign: &&
       "$3" == -s && "$4" == -k && "$5" == "$CERTIFICATE_PASSWORD" &&
       "$6" == "$RUNNER_TEMP/app-signing.keychain-db" ]] || exit 2
    grep -qx import "$MOCK_LOG" || exit 3
  fi
  [[ "$command" != "$MOCK_FAIL" ]] || exit 9
}
mock_codesign() {
  grep -qx set-key-partition-list "$MOCK_LOG" || exit 4
  printf 'codesign\\n' >> "$MOCK_LOG"
  if [[ "$1" == -d ]]; then
    printf '<key>com.apple.security.app-sandbox</key><true/>\\n'
  fi
}
"""


class ReleaseSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Sign app with Developer ID\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        cls.script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        # Substitute only the runner expressions and absolute executable path;
        # keep the actual workflow's commands and error handling under test.
        for expression, variable in (
            ("env.RELEASE_APP_DIR", "RELEASE_APP_DIR"),
            ("env.APP_NAME", "APP_NAME"),
            ("github.workspace", "GITHUB_WORKSPACE"),
        ):
            cls.script = cls.script.replace("${{ " + expression + " }}", "$" + variable)
        if "${{" in cls.script:
            raise AssertionError("Unhandled workflow expression in signing step")
        cls.script, count = re.subn(
            r"(?m)^/usr/bin/codesign(?= )", "mock_codesign", cls.script
        )
        if count != 2:
            raise AssertionError("Expected signing and entitlement inspection commands")

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="release signing ")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.log = self.root / "events"
        self.github_env = self.root / "github-env"

    def run_step(self, fail_command=""):
        self.log.write_text("")
        self.github_env.write_text("")
        env = dict(
            os.environ,
            RUNNER_TEMP=str(self.root),
            CERTIFICATE_BASE64="ZHVtbXk=",  # dummy, not a real certificate
            CERTIFICATE_PASSWORD="dummy password with spaces",
            CERTIFICATE_IDENTITY="Developer ID Application: Test",
            RELEASE_APP_DIR=str(self.root / "release app"),
            APP_NAME="Transnote",
            GITHUB_WORKSPACE=str(ROOT),
            GITHUB_ENV=str(self.github_env),
            MOCK_LOG=str(self.log),
            MOCK_FAIL=fail_command,
        )
        return subprocess.run(
            ["bash", "-c", MOCKS + self.script], env=env, capture_output=True, text=True
        )

    def test_partition_list_is_set_after_import_and_before_signing(self):
        result = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [
                "create-keychain", "set-keychain-settings", "unlock-keychain",
                "import", "set-key-partition-list", "list-keychain",
                "codesign", "codesign",
            ],
        )
        self.assertEqual(self.github_env.read_text(), "SIGNED=1\n")

    def test_keychain_failures_stop_before_signing(self):
        for command in ("import", "set-key-partition-list"):
            with self.subTest(command=command):
                result = self.run_step(fail_command=command)
                self.assertEqual(result.returncode, 9, result.stderr)
                events = self.log.read_text().splitlines()
                self.assertEqual(events[-1], command)
                self.assertNotIn("codesign", events)
                self.assertEqual(self.github_env.read_text(), "")


if __name__ == "__main__":
    unittest.main()
