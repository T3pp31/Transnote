#!/usr/bin/env python3
"""Print the pinned Xcode version shared by CI, Release and Nightly."""

from pathlib import Path
import plistlib
import re
import sys
from xml.parsers.expat import ExpatError


CONFIG = Path(__file__).resolve().parent.parent / "Config/toolchain.plist"


def main():
    try:
        with CONFIG.open("rb") as stream:
            config = plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError) as error:
        print(f"Failed to read {CONFIG}: {error}", file=sys.stderr)
        return 1

    version = config.get("XcodeVersion") if isinstance(config, dict) else None
    # Require a pinned numeric version; never emit multiline Actions output or
    # silently fall back to whichever Xcode happens to be installed on a runner.
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", version):
        print(f"Invalid XcodeVersion in {CONFIG}: expected major.minor[.patch]", file=sys.stderr)
        return 1

    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
