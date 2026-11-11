#!/usr/bin/env python3
"""Exercise the workflow's lockfile check without Xcode or a real Git repository."""

import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
RESOLVED = "LocalTranscriber.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def verification_script():
    lines = (ROOT / ".github/workflows/ci.yml").read_text().splitlines()
    start = lines.index("      - name: Verify Package.resolved is committed")
    if lines[start + 1] != "        run: |":
        raise AssertionError("Expected an inline lockfile verification script")
    body = []
    for line in lines[start + 2:]:
        if line.strip() and not line.startswith("          "):
            break
        body.append(line[10:])
    if not body:
        raise AssertionError("Lockfile verification script is empty")
    return "\n".join(body)


class PackageResolvedCheckTests(unittest.TestCase):
    def test_lockfile_states(self):
        # An untracked file is invisible to git diff even after resolution
        # recreates it. Mock only Git; execute the actual workflow shell body.
        cases = [
            ("committed_unchanged", True, True, False, None),
            ("missing", False, False, False, "Package.resolved not found"),
            ("tracked_missing", False, True, True, "Package.resolved not found"),
            ("regenerated_untracked", True, False, False, "Package.resolved is not tracked"),
            ("committed_modified", True, True, True, "Package.resolved is out of date"),
        ]
        script = verification_script()
        for name, exists, tracked, changed, error in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as work:
                work = Path(work)
                if exists:
                    resolved = work / RESOLVED
                    resolved.parent.mkdir(parents=True)
                    resolved.write_text("resolved dependencies\n")
                mock_git = textwrap.dedent("""\
                    git() {
                      case "$*" in
                        "ls-files --error-unmatch -- $TEST_RESOLVED")
                          return "$TEST_TRACKING_STATUS" ;;
                        "diff --quiet -- $TEST_RESOLVED")
                          return "$TEST_DIFF_STATUS" ;;
                        "diff -- $TEST_RESOLVED")
                          echo 'mock lockfile diff'
                          return 0 ;;
                        *) echo "Unexpected Git arguments: $*" >&2; return 2 ;;
                      esac
                    }
                    """)
                env = dict(os.environ, TEST_RESOLVED=RESOLVED,
                           TEST_TRACKING_STATUS="0" if tracked else "1",
                           TEST_DIFF_STATUS="1" if tracked and changed else "0")
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", mock_git + script], cwd=work,
                    env=env, text=True, capture_output=True, check=False,
                )
                output = result.stdout + result.stderr
                self.assertNotIn("Unexpected Git arguments", output)
                if error is None:
                    self.assertEqual(result.returncode, 0, output)
                else:
                    self.assertNotEqual(result.returncode, 0, output)
                    self.assertIn(error, output)
                    if changed and exists:
                        self.assertIn("mock lockfile diff", output)


if __name__ == "__main__":
    unittest.main()
