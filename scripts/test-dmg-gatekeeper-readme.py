#!/usr/bin/env python3
from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parent.parent
config = plistlib.loads((root / "Config/distribution.plist").read_bytes())
readme = (root / "Config/dmg-gatekeeper-readme.txt").read_text(encoding="utf-8")
method_c = readme.split("【方法 C】システム設定から許可\n", 1)[1].split("\n■", 1)[0]
step = re.search(r"^3\..*(?:\n[ \t]+.*)*", method_c, re.MULTILINE)
if step is None:
    sys.exit("FAIL: 方法 C の許可対象を説明する手順3がありません")
for target in (config["InstallScriptName"], config["AppName"], "このまま開く"):
    if target not in step.group():
        sys.exit(f"FAIL: 方法 C の手順3に {target} の案内がありません")
print("PASS: 方法 C はインストーラーとアプリ本体の許可を案内する")
