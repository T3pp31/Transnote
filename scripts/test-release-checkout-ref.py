#!/usr/bin/env python3
"""Verify that Release normalizes the workflow_dispatch version before checkout."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


class ReleaseCheckoutRefTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        steps = re.split(r"(?m)^      - ", WORKFLOW)[1:]
        cls.steps = steps
        cls.normalize = next(
            (step for step in steps if "name: Normalize checkout ref" in step),
            None,
        )
        cls.checkout = next(
            (step for step in steps if "uses: actions/checkout@" in step),
            None,
        )

    def test_normalize_step_exists_before_checkout(self):
        self.assertIsNotNone(self.normalize, "checkout 前に ref を正規化するステップが必要")
        self.assertIsNotNone(self.checkout)
        self.assertLess(
            self.steps.index(self.normalize),
            self.steps.index(self.checkout),
            "正規化ステップは checkout より前にあること",
        )

    def test_normalize_step_strips_optional_v_prefix_and_adds_it_back(self):
        self.assertIn('version="${RELEASE_VERSION_INPUT#v}"', self.normalize)
        self.assertIn('echo "ref=v${version}" >> "$GITHUB_OUTPUT"', self.normalize)

    def test_normalize_step_rejects_empty_and_unsupported_input(self):
        self.assertIn('if [ -z "$RELEASE_VERSION_INPUT" ]; then', self.normalize)
        self.assertIn('echo "workflow_dispatch requires the version input', self.normalize)
        self.assertIn('if ! [[ "$version" =~ ^[0-9A-Za-z.+-]+$ ]]; then', self.normalize)
        self.assertIn("Release version contains unsupported characters.", self.normalize)

    def test_checkout_uses_normalized_ref(self):
        self.assertRegex(
            self.checkout,
            r"(?m)^          ref: \$\{\{ steps\.checkout_ref\.outputs\.ref \}\}[ \t]*$",
            "checkout は正規化した ref を使うこと",
        )
        self.assertNotIn("github.event.inputs.version", self.checkout)


if __name__ == "__main__":
    unittest.main()
