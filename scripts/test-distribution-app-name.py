#!/usr/bin/env python3
"""配布名の正本と export / DMG / SBOM の連携を macOS ツールなしで検証する。"""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text()

# 外部ツールだけを関数で置き換える。BASH_ENV なので noexec の一時領域でも実行可能。
MOCKS = r'''
mock_plistbuddy() {
  python3 - "$@" <<'PY'
import plistlib, sys
assert sys.argv[1] == "-c"
with open(sys.argv[3], "rb") as stream:
    print(plistlib.load(stream)[sys.argv[2].removeprefix("Print :")])
PY
}
ditto() {
  printf 'ditto\n' >> "$TOOL_LOG"
  cp -R "$1" "$2"
}
codesign() {
  printf 'codesign\n' >> "$TOOL_LOG"
  return 1  # unsigned bundle
}
hdiutil() {
  printf 'hdiutil %s\n' "$1" >> "$TOOL_LOG"
  case "$1" in
    create)
      [[ "$2" == -volname && "$3" == "$APP_NAME" && "$4" == -srcfolder ]] || return 2
      [[ -f "$5/$APP_NAME.app/marker" && -f "$5/distribution.plist" ]] || return 3
      printf 'mock disk image\n' > "${!#}"
      ;;
    convert) cp "$2" "${!#}" ;;
    verify) [[ -s "$2" ]] ;;
    *) return 4 ;;
  esac
}
syft() {
  printf 'syft\n' >> "$TOOL_LOG"
  [[ "$1" == scan && "$3" == --output ]] || return 2
  printf '%s\n' "$2" > "$SCAN_LOG"
  python3 - "$4" "$MOCK_LIBRARIES" <<'PY'
import json, pathlib, sys
output_format, path = sys.argv[1].split("=", 1)
assert output_format == "cyclonedx-json"
components = [{"type": "library", "name": "fixture"}] * int(sys.argv[2])
pathlib.Path(path).write_text(json.dumps({"components": components}))
PY
}
jq() {
  [[ "$1" == '[.components[]? | select(.type == "library")] | length' ]] || return 2
  python3 - "$2" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    print(sum(c.get("type") == "library" for c in json.load(stream)["components"]))
PY
}
'''


def workflow_script(name):
    step = WORKFLOW.split(f"      - name: {name}\n", 1)[1]
    step = step.split("\n      - name:", 1)[0]
    script = textwrap.dedent(step.split("        run: |\n", 1)[1])
    # 絶対パスの macOS ツールとスクリプトの起動方法のみをテスト環境向けに変更。
    script = script.replace("/usr/libexec/PlistBuddy", "mock_plistbuddy")
    script = script.replace("./scripts/", "bash ./scripts/")
    script = script.replace("${{ env.RELEASE_APP_DIR }}", "$RELEASE_APP_DIR")
    if "${{" in script:
        raise AssertionError(f"Unhandled workflow expression in {name}")
    return script


class DistributionAppNameTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory(prefix="distribution name ")
        self.addCleanup(work.cleanup)
        self.root = Path(work.name)
        for directory in ("scripts", "Config"):
            (self.root / directory).mkdir()
        for name in ("export-release-app.sh", "generate-sbom.sh", "create-dmg.sh",
                     "install-transnote.command"):
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        for name in ("distribution.plist", "sbom.plist"):
            shutil.copyfile(ROOT / "Config" / name, self.root / "Config" / name)
        # create-dmg は macOS 専用。export と SBOM は実際の Python フォールバックを使用。
        dmg = self.root / "scripts/create-dmg.sh"
        dmg.write_text(dmg.read_text().replace("/usr/libexec/PlistBuddy", "mock_plistbuddy"))
        self.distribution = self.root / "Config/distribution.plist"
        self.sbom_config = plistlib.loads((self.root / "Config/sbom.plist").read_bytes())
        package = self.root / self.sbom_config["PackageResolvedPath"]
        package.parent.mkdir(parents=True)
        package.write_text('{"pins": []}')
        self.github_env = self.root / "github-env"
        self.github_output = self.root / "github-output"
        self.log = self.root / "tools"
        for path in (self.github_env, self.github_output, self.log):
            path.write_text("")
        mocks = self.root / "mocks.bash"
        mocks.write_text(MOCKS)
        self.env = dict(os.environ, BASH_ENV=str(mocks), GITHUB_ENV=str(self.github_env),
                        GITHUB_OUTPUT=str(self.github_output), TOOL_LOG=str(self.log),
                        SCAN_LOG=str(self.root / "scan"), MOCK_LIBRARIES="1",
                        RELEASE_APP_DIR="build/release", RELEASE_VERSION="1.2.3",
                        SYFT_PATH="syft")
        self.env.pop("TRANSNOTE_SBOM_CONFIG", None)

    def run_bash(self, *args):
        return subprocess.run(["bash", *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True)

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def set_name(self, name):
        config = plistlib.loads(self.distribution.read_bytes())
        config["AppName"] = name
        self.distribution.write_bytes(plistlib.dumps(config))

    def resolve_name(self):
        self.success(self.run_bash("-c", workflow_script("Read distribution config")))
        values = dict(line.split("=", 1) for line in self.github_env.read_text().splitlines())
        self.env.update(values)
        return values

    def test_default_name_and_sbom_settings(self):
        expected = plistlib.loads(self.distribution.read_bytes())["AppName"]
        self.assertNotIn("AppName", self.sbom_config)
        self.assertEqual(self.resolve_name(), {
            "APP_NAME": expected, "ARCHIVE_PATH": f"build/{expected}.xcarchive"})
        for key, value in (("AppName", expected),
                           ("SyftVersion", self.sbom_config["SyftVersion"]),
                           ("CIArtifactName", self.sbom_config["CIArtifactName"])):
            self.assertEqual(self.success(self.run_bash("scripts/generate-sbom.sh", "--print", key)), value)

    def test_rename_propagates_to_export_dmg_and_both_sboms(self):
        name = "別名 App"
        self.set_name(name)  # 配布設定だけを変更する。
        values = self.resolve_name()
        source = self.root / values["ARCHIVE_PATH"] / "Products/Applications" / f"{name}.app"
        source.mkdir(parents=True)
        (source / "marker").write_text("original bundle")
        self.success(self.run_bash("-c", workflow_script("Export app")))
        exported = self.root / "build/release" / f"{name}.app"
        self.assertEqual((exported / "marker").read_text(), "original bundle")
        self.success(self.run_bash("scripts/export-release-app.sh", "--output", "build/release",
                                  "--verify-only"))
        self.success(self.run_bash("-c", workflow_script("Create DMG")))
        versioned = self.root / "build/dist" / f"{name}-1.2.3.dmg"
        self.assertEqual(versioned.read_bytes(),
                         (self.root / "build/dist" / f"{name}.dmg").read_bytes())
        outputs = dict(line.split("=", 1) for line in self.github_output.read_text().splitlines())
        self.assertEqual(outputs["versioned_dmg_name"], versioned.name)
        self.assertEqual(outputs["latest_dmg_name"], f"{name}.dmg")
        for mode, filename, scan_target in (
            ("release", f"{name}-1.2.3.cdx.json", exported),
            ("ci", f"{name}-sbom.cdx.json", self.root / self.sbom_config["PackageResolvedPath"]),
        ):
            path = self.success(self.run_bash("scripts/generate-sbom.sh", "--mode", mode,
                                              "--version", "1.2.3"))
            self.assertEqual(Path(path), self.root / "build/sbom" / filename)
            self.assertTrue(json.loads(Path(path).read_text())["components"])
            self.assertEqual((self.root / "scan").read_text().strip(), str(scan_target))

    def test_custom_sbom_config_cannot_override_app_name(self):
        self.set_name("Renamed App")
        config = dict(self.sbom_config, AppName="Stale Name", CIArtifactName="custom-artifact",
                      CIOutputFilename="{AppName}-custom.cdx.json")
        custom = self.root / "custom-sbom.plist"
        custom.write_bytes(plistlib.dumps(config))
        args = ("scripts/generate-sbom.sh", "--config", str(custom))
        self.assertEqual(self.success(self.run_bash(*args, "--print", "AppName")), "Renamed App")
        self.assertEqual(self.success(self.run_bash(*args, "--print", "CIArtifactName")), "custom-artifact")
        path = self.success(self.run_bash(*args, "--mode", "ci"))
        self.assertEqual(Path(path).name, "Renamed App-custom.cdx.json")

    def test_invalid_distribution_stops_before_touching_outputs(self):
        original = self.distribution.read_bytes()
        name = plistlib.loads(original)["AppName"]
        archive = self.root / "valid.xcarchive"
        source = archive / "Products/Applications" / f"{name}.app"
        source.mkdir(parents=True)
        (source / "marker").write_text("new bundle")
        marker = self.root / "build/release" / f"{name}.app/marker"
        marker.parent.mkdir(parents=True)
        marker.write_text("keep existing export")
        for invalid in (None, {}, {"AppName": ""}):
            with self.subTest(config=invalid):
                self.distribution.write_bytes(original)
                if invalid is None:
                    self.distribution.unlink()
                else:
                    self.distribution.write_bytes(plistlib.dumps(invalid))
                for args in (
                    ("-c", workflow_script("Read distribution config")),
                    ("scripts/export-release-app.sh", "--archive", str(archive),
                     "--output", "build/release"),
                    ("scripts/generate-sbom.sh", "--mode", "ci"),
                ):
                    result = self.run_bash(*args)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertTrue(result.stderr)
                self.assertEqual(self.github_env.read_text(), "")
                self.assertEqual(self.log.read_text(), "")
                self.assertEqual(marker.read_text(), "keep existing export")
                self.assertFalse((self.root / "build/sbom").exists())
                # SBOM 固有の設定値の取得には配布設定を必要としない。
                self.assertEqual(self.success(self.run_bash("scripts/generate-sbom.sh", "--print",
                                                            "SyftVersion")), self.sbom_config["SyftVersion"])

    def test_workflow_rejects_multiline_name_without_exporting_environment(self):
        self.set_name("App\nOTHER=value")
        result = self.run_bash("-c", workflow_script("Read distribution config"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.github_env.read_text(), "")

    def test_sbom_still_rejects_empty_library_list(self):
        self.env["MOCK_LIBRARIES"] = "0"
        result = self.run_bash("scripts/generate-sbom.sh", "--mode", "ci")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SBOM has no library components:", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
