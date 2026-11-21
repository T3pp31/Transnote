#!/usr/bin/env python3
"""Verify that NSLocalizedString keys used by progress display and file drop have English translations.

ソース中のキーを直接抽出してカタログと突合するため、実装側のキーが変わって
カタログのエントリが孤立した場合や、生の文字列リテラルに戻された場合も検出できる。
"""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent
CATALOG = json.loads((ROOT / "LocalTranscriber/Localizable.xcstrings").read_text(encoding="utf-8"))
SOURCES = [
    ROOT / "LocalTranscriber/Domain/TranscriptionProgressDisplay.swift",
    ROOT / "LocalTranscriber/Presentation/FileDropView.swift",
]
KEY_PATTERN = re.compile(r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"', re.S)


def english_value(key):
    entry = CATALOG.get("strings", {}).get(key)
    if entry is None:
        return None
    return entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")


class LocalizationKeyTests(unittest.TestCase):
    def test_source_keys_have_english_translation(self):
        for source in SOURCES:
            keys = KEY_PATTERN.findall(source.read_text(encoding="utf-8"))
            self.assertTrue(keys, f"{source.name} から NSLocalizedString のキーを抽出できること")
            for key in keys:
                with self.subTest(source=source.name, key=key):
                    value = english_value(key)
                    self.assertIsNotNone(value, "カタログに英語訳が登録されていること")
                    if re.search(r"[぀-ヿ一-鿿]", key):
                        self.assertNotEqual(value, key, "英語訳がキーと同じ日本語のままでないこと")

    def test_drop_error_messages_are_localized(self):
        source = (ROOT / "LocalTranscriber/Presentation/FileDropView.swift").read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r'dropErrorMessage = "', source),
            "dropErrorMessage には生の文字列リテラルではなく NSLocalizedString を使うこと",
        )


if __name__ == "__main__":
    unittest.main()
