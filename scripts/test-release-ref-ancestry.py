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
            i for i, step in enumerate(cls.steps) if "actions/checkout@" in step
        )
        cls.verify = next(
            (step for step in cls.steps if "name: Verify release commit is on main" in step),
            None,
        )

    def test_checkout_fetches_full_history_for_ancestry_check(self):
        checkout = self.steps[self.checkout_index]
        self.assertRegex(checkout, r"(?m)^          fetch-depth: 0$")

    def test_ancestry_check_runs_before_build_steps(self):
        self.assertIsNotNone(self.verify, "main の祖先検証ステップが必要")
        verify_index = self.steps.index(self.verify)
        self.assertGreater(verify_index, self.checkout_index)
        for name in ("Read Xcode version", "Archive Release build", "Sign app with Developer ID"):
            step_index = next(
                i for i, step in enumerate(self.steps) if f"name: {name}" in step
            )
            self.assertLess(verify_index, step_index, f"{name} より前に検証すること")

    def test_ancestry_check_rejects_commits_not_on_main(self):
        self.assertIn("git fetch --no-tags origin main", self.verify)
        self.assertIn("git merge-base --is-ancestor HEAD origin/main", self.verify)
        self.assertIn("must be an ancestor of main", self.verify)


if __name__ == "__main__":
    unittest.main()
