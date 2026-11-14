#!/usr/bin/env python3
"""Guard Release's direct Action references and checkout credential handling."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent


class ReleaseActionSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        # Match the workflow's step mappings, not text inside inline run scripts.
        cls.actions = []
        for step in re.split(r"(?m)^      - ", workflow)[1:]:
            action = re.search(r"(?m)^(?:        )?uses: ([^\s#]+)", step)
            if action:
                cls.actions.append((action.group(1), step))

    def test_all_direct_actions_are_pinned_to_full_commit_shas(self):
        repositories = [action.split("@", 1)[0] for action, _ in self.actions]
        # Fail closed if the expected security-sensitive steps were not found.
        self.assertIn("actions/checkout", repositories)
        self.assertIn("actions/attest-build-provenance", repositories)
        for action, _ in self.actions:
            with self.subTest(action=action):
                self.assertRegex(action, r"^[^@\s]+@[0-9a-f]{40}$")

    def test_checkout_explicitly_disables_persisted_credentials(self):
        checkouts = [step for action, step in self.actions
                     if action.startswith("actions/checkout@")]
        self.assertEqual(len(checkouts), 1)
        for step in checkouts:
            self.assertRegex(
                step,
                r"(?m)^        with:\n(?:          .*\n)*"
                r"          persist-credentials: false(?:[ \t]+#.*)?[ \t]*(?:\n|$)",
            )


if __name__ == "__main__":
    unittest.main()
