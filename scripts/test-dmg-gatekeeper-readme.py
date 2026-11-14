#!/usr/bin/env python3
"""署名案内の共有と Release 本文の状態別表示を実際のシェルで検証する。"""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parent.parent


class GatekeeperReadmeTests(unittest.TestCase):
    def test_method_c_describes_both_permission_targets(self):
        config = plistlib.loads((ROOT / "Config/distribution.plist").read_bytes())
        readme = (ROOT / "Config/dmg-gatekeeper-readme.txt").read_text(encoding="utf-8")
        method_c = readme.split("【方法 C】システム設定から許可\n", 1)[1].split("\n■", 1)[0]
        step = re.search(r"^3\..*(?:\n[ \t]+.*)*", method_c, re.MULTILINE)
        self.assertIsNotNone(step, "方法 C の許可対象を説明する手順3がありません")
        for target in (config["InstallScriptName"], config["AppName"], "このまま開く"):
            self.assertIn(target, step.group())

    def test_readme_keeps_build_specific_notice_in_one_placeholder(self):
        readme = (ROOT / "Config/dmg-gatekeeper-readme.txt").read_text(encoding="utf-8")
        self.assertEqual(readme.count("@SECURITY_NOTICE@"), 1)
        for stale_claim in ("未署名", "署名がないため", "署名）をおこなわず", "署名済み"):
            self.assertNotIn(stale_claim, readme)

    def test_release_body_uses_shared_notice_for_each_signing_state(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Prepare release notes\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        for expression, value in (
            ("steps.dmg.outputs.versioned_dmg_name", "Transnote-1.2.3.dmg"),
            ("steps.dmg.outputs.latest_dmg_name", "Transnote.dmg"),
            ("steps.checksum.outputs.versioned_hash", "a" * 64),
            ("steps.checksum.outputs.latest_hash", "a" * 64),
        ):
            script = script.replace("${{ " + expression + " }}", value)
        self.assertNotIn("${{", script, "Unhandled workflow expression")
        self.assertIn("source ./scripts/release-security-notice.sh", script)

        unsigned_note = "現時点では未署名ビルドを配布しています。"
        signed_notice = "Developer ID で署名済みのビルドです。公証は行われていません。"
        notarized_notice = "Developer ID で署名・公証済みのビルドです。"
        for flags, notice, signature in (
            ({}, "署名）をせずに配布しているため", unsigned_note),
            ({"SIGNED": "0", "NOTARIZED": "0"}, "署名）をせずに配布しているため", unsigned_note),
            ({"SIGNED": "1"}, signed_notice, "公証には Apple ID 等の secrets 設定が必要です。"),
            ({"SIGNED": "1", "NOTARIZED": "1"}, notarized_notice, "このビルドは Developer ID で署名・公証済みです。"),
            ({"NOTARIZED": "1"}, notarized_notice, "このビルドは Developer ID で署名・公証済みです。"),
        ):
            with self.subTest(flags=flags), tempfile.TemporaryDirectory(prefix="release notes ") as work:
                work = Path(work)
                (work / "scripts").mkdir()
                shutil.copy(ROOT / "scripts/release-security-notice.sh", work / "scripts")
                env = dict(os.environ)
                env.pop("SIGNED", None)
                env.pop("NOTARIZED", None)
                env.update(APP_NAME="Transnote")
                env.update(flags)
                result = subprocess.run(
                    ["bash", "-c", script], cwd=work, env=env, capture_output=True, text=True
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                body = (work / "release_body.md").read_text()
                self.assertIn(notice, body.splitlines()[0])
                self.assertIn(signature, body.splitlines()[-1])
                self.assertIn("Transnote.dmg.sha256", body)
                self.assertIn("shasum -a 256 -c Transnote-1.2.3.dmg.sha256", body)
                if flags.get("SIGNED") == "1" or flags.get("NOTARIZED") == "1":
                    self.assertNotIn("未署名", body)
                    self.assertNotIn("署名）をせず", body)


if __name__ == "__main__":
    unittest.main()
