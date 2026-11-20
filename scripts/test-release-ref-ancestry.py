#!/usr/bin/env python3
"""Release が main の祖先コミットだけをビルド対象にすることを検証する。"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


class ReleaseRefAncestryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.steps = re.split(r"(?m)^      - ", WORKFLOW)[1:]
        cls.checkout_index = next(
            (i for i, step in enumerate(cls.steps) if "actions/checkout@" in step), None
        )
        if cls.checkout_index is None:
            raise AssertionError("actions/checkout ステップが見つからない")
        cls.verify = next(
            (step for step in cls.steps if "name: Verify release commit is on main" in step),
            None,
        )

    def test_checkout_fetches_full_history_for_ancestry_check(self):
        checkout = self.steps[self.checkout_index]
        self.assertRegex(checkout, r"(?m)^          fetch-depth: 0$")

    def test_ancestry_check_runs_right_after_checkout(self):
        self.assertIsNotNone(self.verify, "main の祖先検証ステップが必要")
        self.assertEqual(
            self.steps.index(self.verify),
            self.checkout_index + 1,
            "checkout 直後に祖先検証を行うこと",
        )

    def test_ancestry_check_rejects_commits_not_on_main(self):
        self.assertIsNotNone(self.verify, "main の祖先検証ステップが必要")
        self.assertIn(
            "git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main",
            self.verify,
        )
        # 同名タグ origin/main で回避されないよう完全修飾 ref を使う。
        self.assertIn(
            'git merge-base --is-ancestor "$head_sha" refs/remotes/origin/main',
            self.verify,
        )
        self.assertIn("if ! git merge-base", self.verify)
        self.assertIn("exit 1", self.verify)
        self.assertIn("set -euo pipefail", self.verify)
        self.assertNotIn("continue-on-error", self.verify)
        self.assertNotRegex(self.verify, r"(?m)^        if:")

    def test_failure_message_reports_checked_ref(self):
        self.assertIsNotNone(self.verify, "main の祖先検証ステップが必要")
        self.assertIn("RELEASE_REF:", self.verify)
        self.assertIn("$RELEASE_REF ($head_sha) must be an ancestor of main", self.verify)


if __name__ == "__main__":
    unittest.main()
