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

    def test_build_provenance_attestation_covers_all_release_artifacts_and_permissions(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"(?m)^  id-token: write$")
        self.assertRegex(workflow, r"(?m)^  attestations: write$")

        steps = re.split(r"(?m)^      - ", workflow)[1:]
        names = [step.splitlines()[0] for step in steps]
        checksum_idx = names.index("name: Compute SHA256 checksums")
        attest_idx = names.index("name: Attest build provenance")
        release_idx = names.index("name: Create GitHub Release")
        self.assertLess(checksum_idx, attest_idx)
        self.assertLess(attest_idx, release_idx)

        attest_step = steps[attest_idx]
        self.assertNotRegex(attest_step, r"(?m)^        (if|continue-on-error):")
        self.assertNotRegex(attest_step, r"(?m)^          subject-name:")

        subject_match = re.search(
            r"(?m)^          subject-path: \|\n((?:            [^\n]+\n)+)", attest_step
        )
        self.assertIsNotNone(subject_match, "subject-path block not found")
        attested_paths = [line.strip() for line in subject_match.group(1).splitlines()]

        release_step = steps[release_idx]
        files_match = re.search(
            r"(?m)^          files: \|\n((?:            [^\n]+(?:\n|$))+)", release_step
        )
        self.assertIsNotNone(files_match, "release files block not found")
        release_files = [line.strip() for line in files_match.group(1).splitlines() if line.strip()]
        self.assertEqual(
            attested_paths,
            release_files,
            "GitHub Release に添付する全成果物を build provenance attestation の対象に含めること",
        )


if __name__ == "__main__":
    unittest.main()
