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


class CISBOMUploadPathTests(unittest.TestCase):
    def test_upload_sbom_uses_generated_sbom_dir_output(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        upload_block = workflow.split("      - name: Upload SBOM artifact\n", 1)[1]
        upload_block = upload_block.split("\n  lint:\n", 1)[0]
        self.assertIn("path: ${{ steps.sbom.outputs.sbom_dir }}/", upload_block)
        self.assertNotIn("build/sbom", upload_block)

        lines = workflow.splitlines()
        start = lines.index("      - name: Generate SBOM")
        run_index = lines.index("        run: |", start)
        body = []
        for line in lines[run_index + 1:]:
            if line.strip() and not line.startswith("          "):
                break
            body.append(line[10:])
        script = "\n".join(body)

        with tempfile.TemporaryDirectory() as work_dir:
            work = Path(work_dir)
            (work / "scripts").mkdir()
            stub = work / "scripts/generate-sbom.sh"
            stub.write_text(
                "#!/usr/bin/env bash\n"
                "case \"$*\" in\n"
                "  '--mode ci') echo '/custom/out/sbom/Transnote-sbom.cdx.json' ;;\n"
                "  '--print CIArtifactName') echo 'sbom-cyclonedx' ;;\n"
                "  '--print CIArtifactRetentionDays') echo '30' ;;\n"
                "  *) exit 2 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            stub.chmod(0o755)
            github_output = work / "github-output"
            github_output.write_text("", encoding="utf-8")
            env = dict(os.environ, GITHUB_OUTPUT=str(github_output))
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", script],
                cwd=work,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            outputs = dict(
                line.split("=", 1)
                for line in github_output.read_text(encoding="utf-8").splitlines()
            )
            self.assertEqual(outputs["sbom_path"], "/custom/out/sbom/Transnote-sbom.cdx.json")
            self.assertEqual(outputs["sbom_dir"], "/custom/out/sbom")


if __name__ == "__main__":
    unittest.main()
