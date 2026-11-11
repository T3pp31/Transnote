#!/usr/bin/env python3
"""Verify Xcode target build phase references and Frameworks phases."""

import re
import sys
from pathlib import Path


PBXPROJ = Path("LocalTranscriber.xcodeproj/project.pbxproj")


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def main():
    text = PBXPROJ.read_text(encoding="utf-8")
    definitions = {
        match.group(1): match.group(2)
        for match in re.finditer(
            r"^\t\t([A-F0-9]{24})(?: /\*.*?\*/)? = \{\n\t\t\tisa = (\w+);",
            text,
            re.MULTILINE,
        )
    }

    # Extract complete target objects before looking for buildPhases so a
    # missing list cannot consume the next target's references.
    targets = {
        match.group(1): match.group(2)
        for match in re.finditer(
            r"^\t\t([A-F0-9]{24})(?: /\*[^\n]*?\*/)? = \{\n"
            r"\t\t\tisa = PBXNativeTarget;\n(.*?)^\t\t};",
            text,
            re.MULTILINE | re.DOTALL,
        )
    }
    target_ids = {object_id for object_id, isa in definitions.items() if isa == "PBXNativeTarget"}
    if targets.keys() != target_ids:
        return fail("could not extract all PBXNativeTarget objects")

    phase_references = []
    for target_id, body in targets.items():
        phases = re.search(
            r"^\t\t\tbuildPhases = \((.*?)\);", body, re.MULTILINE | re.DOTALL
        )
        if phases is None:
            return fail(f"target {target_id} has no readable buildPhases list")
        phase_references.extend(
            (target_id, phase_id)
            for phase_id in re.findall(r"([A-F0-9]{24})(?: /\*.*?\*/)?", phases.group(1))
        )

    if not phase_references:
        return fail("no PBXNativeTarget build phase references found")

    for target_id, phase_id in phase_references:
        if phase_id not in definitions:
            return fail(f"target {target_id} references undefined build phase {phase_id}")

    frameworks_phases = {
        phase_id
        for phase_id, isa in definitions.items()
        if isa == "PBXFrameworksBuildPhase"
    }
    referenced_frameworks = {
        phase_id
        for target_id, phase_id in phase_references
        if definitions[phase_id] == "PBXFrameworksBuildPhase"
    }

    if not frameworks_phases:
        return fail("no PBXFrameworksBuildPhase definitions found")
    if frameworks_phases != referenced_frameworks:
        return fail("Frameworks phase definitions and target references do not match")

    print(
        f"OK: {len(phase_references)} build phase references resolve; "
        f"{len(frameworks_phases)} Frameworks phases are referenced"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
