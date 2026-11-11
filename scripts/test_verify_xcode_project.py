#!/usr/bin/env python3
"""Regression tests for the Xcode project structure verifier."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


VERIFIER = Path(__file__).with_name("verify-xcode-project.py").resolve()
TARGETS = ["A" * 24, "B" * 24, "C" * 24]
FRAMEWORKS = "D" * 24
OTHER_FRAMEWORKS = "E" * 24
UNDEFINED = "F" * 24


def object_block(object_id, isa, body="", comment=" /* Test */"):
    return (
        f"\t\t{object_id}{comment} = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"{body}"
        "\t\t};\n"
    )


def build_phases(*phase_ids):
    references = "".join(f"\t\t\t\t{phase_id} /* Frameworks */,\n" for phase_id in phase_ids)
    return f"\t\t\tbuildPhases = (\n{references}\t\t\t);\n"


class VerifyXcodeProjectTests(unittest.TestCase):
    def verify(self, objects):
        with tempfile.TemporaryDirectory() as work:
            project = Path(work) / "LocalTranscriber.xcodeproj"
            project.mkdir()
            (project / "project.pbxproj").write_text(
                "// !$*UTF8*$!\n{\n\tobjects = {\n" + objects + "\t};\n}\n",
                encoding="utf-8",
            )
            return subprocess.run(
                [sys.executable, str(VERIFIER)],
                cwd=work,
                capture_output=True,
                text=True,
                check=False,
            )

    def assert_failure(self, result, message):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertNotIn("OK:", result.stdout)

    def test_multiple_targets_resolve_their_own_phases(self):
        objects = object_block("1" * 24, "PBXGroup")
        objects += object_block(TARGETS[0], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(
            TARGETS[1], "PBXNativeTarget", build_phases(OTHER_FRAMEWORKS), comment=""
        )
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        objects += object_block(OTHER_FRAMEWORKS, "PBXFrameworksBuildPhase")
        result = self.verify(objects)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2 build phase references resolve; 2 Frameworks phases", result.stdout)

    def test_missing_build_phases_fails_at_every_target_position(self):
        # Share the sole Frameworks phase so the global Frameworks check cannot
        # accidentally mask a missing target list with an unreferenced phase.
        for missing_index in range(len(TARGETS)):
            with self.subTest(missing_index=missing_index):
                objects = "".join(
                    object_block(
                        target_id,
                        "PBXNativeTarget",
                        "" if index == missing_index else build_phases(FRAMEWORKS),
                    )
                    for index, target_id in enumerate(TARGETS)
                )
                objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
                self.assert_failure(self.verify(objects), f"target {TARGETS[missing_index]}")

    def test_unrecognized_indentation_does_not_borrow_next_target_phases(self):
        phases = build_phases(UNDEFINED).replace("\t\t\tbuildPhases", "            buildPhases")
        objects = object_block(TARGETS[0], "PBXNativeTarget", phases)
        objects += object_block(TARGETS[1], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        self.assert_failure(self.verify(objects), f"target {TARGETS[0]}")

    def test_unterminated_list_does_not_read_past_object_end(self):
        objects = object_block(TARGETS[0], "PBXNativeTarget", "\t\t\tbuildPhases = (\n")
        objects += object_block(TARGETS[1], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        self.assert_failure(self.verify(objects), f"target {TARGETS[0]}")

    def test_target_without_header_comment_is_not_skipped(self):
        objects = object_block(TARGETS[0], "PBXNativeTarget", comment="")
        objects += object_block(TARGETS[1], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        self.assert_failure(self.verify(objects), f"target {TARGETS[0]}")

    def test_incomplete_target_objects_are_not_silently_skipped(self):
        for incomplete_index in range(2):
            with self.subTest(incomplete_index=incomplete_index):
                objects = object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
                for index, target_id in enumerate(TARGETS[:2]):
                    target = object_block(target_id, "PBXNativeTarget", build_phases(FRAMEWORKS))
                    if index == incomplete_index:
                        target = target.replace("\t\t};\n", "")
                    objects += target
                self.assert_failure(
                    self.verify(objects), "could not extract all PBXNativeTarget objects"
                )

    def test_later_target_undefined_phase_reports_correct_target(self):
        objects = object_block(TARGETS[0], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(TARGETS[1], "PBXNativeTarget", build_phases(UNDEFINED))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        self.assert_failure(
            self.verify(objects),
            f"target {TARGETS[1]} references undefined build phase {UNDEFINED}",
        )

    def test_unreferenced_frameworks_phase_still_fails(self):
        objects = object_block(TARGETS[0], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        objects += object_block(OTHER_FRAMEWORKS, "PBXFrameworksBuildPhase")
        self.assert_failure(
            self.verify(objects), "Frameworks phase definitions and target references do not match"
        )

    def test_empty_list_is_not_treated_as_missing(self):
        objects = object_block(TARGETS[0], "PBXNativeTarget", build_phases())
        objects += object_block(TARGETS[1], "PBXNativeTarget", build_phases(FRAMEWORKS))
        objects += object_block(FRAMEWORKS, "PBXFrameworksBuildPhase")
        result = self.verify(objects)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 build phase references resolve", result.stdout)


if __name__ == "__main__":
    unittest.main()
