#!/usr/bin/env python3
"""Portable installer regression tests using local bundles and mocked macOS tools."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
MOCK = r'''#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import sys
import time

command = sys.argv[1]
args = sys.argv[2:]
run = Path(os.environ["MOCK_RUN"])
with (run / "events").open("a") as log:
    log.write(command + " " + " ".join(args) + "\n")
if command == "PlistBuddy":
    try:
        with open(args[2], "rb") as file:
            value = plistlib.load(file)
        for key in args[1].removeprefix("Print :").split(":"):
            value = value[int(key)] if isinstance(value, list) else value[key]
        print(value)
    except (KeyError, IndexError):
        sys.exit(1)
elif command == "hdiutil" and args == ["info"]:
    custom_info = os.environ.get("MOCK_HDIUTIL_INFO")
    if custom_info is not None:
        sys.stdout.write(custom_info)
    else:
        print("image-path : " + os.environ["MOCK_DMG"])
        print(os.environ["MOCK_VOLUME"])
elif command == "hdiutil" and args and args[0] == "detach":
    if os.environ.get("MOCK_DETACH_FAIL") == "1":
        sys.exit(16)
elif command == "shasum":
    print(hashlib.sha256(Path(args[2]).read_bytes()).hexdigest() + "  " + args[2])
elif command == "spctl":
    if os.environ.get("MOCK_SPCTL_PASS") == "1":
        sys.exit(0)
    sys.exit(3)
elif command == "ditto":
    deployment = args[1] == os.environ["MOCK_TARGET"]
    if deployment and os.environ.get("MOCK_PAUSE") == "1":
        (run / "ready").touch()
        deadline = time.monotonic() + 15
        while not (run / "release").exists():
            if time.monotonic() > deadline:
                sys.exit(9)
            time.sleep(0.02)
    if os.environ.get("MOCK_FAIL") == ("deploy" if deployment else "stage"):
        sys.exit(7)
    shutil.copytree(args[0], args[1], dirs_exist_ok=True)
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.work_dir = tempfile.TemporaryDirectory(prefix="transnote-tests-")
        self.addCleanup(self.work_dir.cleanup)
        self.work = Path(self.work_dir.name)
        self.volume = self.work / "Volumes" / "Transnote"
        self.volume.mkdir(parents=True)
        self.applications = self.work / "Applications with spaces"
        self.applications.mkdir()
        self.target = self.applications / "Transnote.app"
        self.lock = self.applications / ".transnote-install.lock"
        self.tmp = self.work / "tmp"
        self.tmp.mkdir()
        self.mock = self.work / "mock.py"
        self.mock.write_text(MOCK)
        # Shell functions also work on sandboxes with noexec temporary directories.
        self.bash_env = self.work / "mock-env.sh"
        self.bash_env.write_text("\n".join(
            f'{name}() {{ python3 "$MOCK_SCRIPT" {command} "$@"; }}'
            for name, command in (("mock_plistbuddy", "PlistBuddy"), ("hdiutil", "hdiutil"),
                                  ("ditto", "ditto"), ("osascript", "osascript"),
                                  ("open", "open"), ("xattr", "xattr"), ("sleep", "sleep"),
                                  ("shasum", "shasum"), ("spctl", "spctl"))
        ) + "\n")
        self.dmg = self.work / "Transnote.dmg"
        self.dmg.write_bytes(b"local dmg fixture")
        Path(str(self.dmg) + ".sha256").write_text(hashlib.sha256(self.dmg.read_bytes()).hexdigest())
        config = (ROOT / "Config/distribution.plist").read_bytes()
        (self.volume / "distribution.plist").write_bytes(config)
        self.bundle_id = plistlib.loads(config)["BundleIdentifier"]
        self.make_app(self.volume / "Transnote.app", "new")
        self.make_app(self.target, "old")
        # Only relocate OS-specific absolute paths; checksum and install logic run unchanged.
        script = (ROOT / "scripts/install-transnote.command").read_text()
        script = script.replace("/usr/libexec/PlistBuddy", "mock_plistbuddy")
        script = script.replace("/Volumes/", str(self.work / "Volumes") + "/")
        self.installer = self.volume / "install.command"
        self.installer.write_text(script)
        self.processes = []
        self.addCleanup(self.stop_processes)

    def make_app(self, path, marker):
        (path / "Contents").mkdir(parents=True)
        (path / "Contents" / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleIdentifier": self.bundle_id})
        )
        (path / "marker").write_text(marker)

    def start(self, name, **options):
        run = self.work / name
        run.mkdir()
        env = dict(os.environ, BASH_ENV=str(self.bash_env), MOCK_SCRIPT=str(self.mock),
                   TMPDIR=str(self.tmp), TRANSNOTE_INSTALL_DIR=str(self.applications),
                   MOCK_RUN=str(run), MOCK_DMG=str(self.dmg), MOCK_VOLUME=str(self.volume),
                   MOCK_TARGET=str(self.target), **options)
        proc = subprocess.Popen(["bash", str(self.installer)], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append((proc, run))
        return proc, run

    def stop_processes(self):
        for proc, run in self.processes:
            (run / "release").touch()
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()

    def result(self, proc):
        stdout, stderr = proc.communicate(timeout=10)
        return proc.returncode, stdout + stderr

    def wait_ready(self, proc, run):
        deadline = time.monotonic() + 10
        while not (run / "ready").exists():
            if proc.poll() is not None:
                self.fail("installer exited before deployment barrier: " + self.result(proc)[1]
                          + "\n" + (run / "events").read_text())
            if time.monotonic() > deadline:
                self.fail("installer did not reach deployment barrier")
            time.sleep(0.02)

    def assert_clean(self):
        self.assertFalse(self.lock.exists(), "installer left its lock behind")
        self.assertEqual(list(self.tmp.iterdir()), [], "installer left stage/backup behind")

    def assert_no_install(self, run):
        events = (run / "events").read_text()
        for event in ("ditto ", "open ", "xattr ", "to quit", "インストールしました"):
            self.assertNotIn(event, events)

    def test_concurrent_install_is_rejected_until_rollback_finishes(self):
        self.check_concurrent_install("deploy", "old")

    def test_concurrent_install_is_rejected_until_success_finishes(self):
        self.check_concurrent_install("", "new")

    def check_concurrent_install(self, failure, expected):
        first, first_run = self.start("first", MOCK_PAUSE="1", MOCK_FAIL=failure)
        self.wait_ready(first, first_run)
        self.assertFalse(self.target.exists(), "barrier must follow backup of old app")
        second, second_run = self.start("second")
        self.assertNotEqual(self.result(second)[0], 0, "concurrent installer reported success")
        self.assert_no_install(second_run)
        self.assertIn("既にインストール処理中", (second_run / "events").read_text())
        self.assertTrue(self.lock.is_dir(), "rejected installer removed the owner's lock")
        self.assertFalse(self.target.exists(), "rejected installer changed the shared target")
        (first_run / "release").touch()
        code, output = self.result(first)
        if failure:
            self.assertNotEqual(code, 0, output)
            self.assertNotIn("インストールしました", (first_run / "events").read_text())
        else:
            self.assertEqual(code, 0, output)
            self.assertIn("インストールしました", (first_run / "events").read_text())
        self.assertEqual((self.target / "marker").read_text(), expected)
        self.assert_clean()
        retry, _ = self.start("retry")
        self.assertEqual(self.result(retry)[0], 0)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()

    def test_existing_lock_is_not_removed(self):
        self.lock.mkdir()
        (self.lock / "owner").write_text("other installer")
        proc, run = self.start("locked")
        self.assertNotEqual(self.result(proc)[0], 0)
        self.assert_no_install(run)
        self.assertEqual((self.lock / "owner").read_text(), "other installer")
        self.assertEqual((self.target / "marker").read_text(), "old")
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_fresh_install_releases_lock(self):
        shutil.rmtree(self.target)
        proc, run = self.start("fresh")
        self.assertEqual(self.result(proc)[0], 0)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assertIn("インストールしました", (run / "events").read_text())
        self.assert_clean()

    def test_staging_failure_releases_lock_without_changing_old_app(self):
        proc, run = self.start("stage-fail", MOCK_FAIL="stage")
        self.assertNotEqual(self.result(proc)[0], 0)
        self.assertIn("新バージョンのコピーに失敗", (run / "events").read_text())
        self.assertNotIn("インストールしました", (run / "events").read_text())
        self.assertEqual((self.target / "marker").read_text(), "old")
        self.assert_clean()

    def test_bundle_id_mismatch_releases_lock_without_replacing_app(self):
        (self.target / "Contents" / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleIdentifier": "unrelated.app"})
        )
        proc, run = self.start("mismatch")
        self.assertNotEqual(self.result(proc)[0], 0)
        self.assertIn("Bundle ID が一致しません", (run / "events").read_text())
        self.assertEqual((self.target / "marker").read_text(), "old")
        self.assert_clean()

    def test_term_rolls_back_before_releasing_lock(self):
        proc, run = self.start("terminated", MOCK_PAUSE="1")
        self.wait_ready(proc, run)
        proc.send_signal(signal.SIGTERM)
        (run / "release").touch()
        self.assertEqual(self.result(proc)[0], 143)
        self.assertEqual((self.target / "marker").read_text(), "old")
        self.assertNotIn("インストールしました", (run / "events").read_text())
        self.assert_clean()

    def test_signed_notarized_app_skips_quarantine_removal(self):
        proc, run = self.start("signed", MOCK_SPCTL_PASS="1")
        self.assertEqual(self.result(proc)[0], 0)
        events = (run / "events").read_text()
        self.assertIn("spctl --assess --type execute ", events)
        self.assertNotIn("xattr ", events)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()

    def test_unsigned_app_removes_quarantine_after_checksum_verification(self):
        proc, run = self.start("unsigned", MOCK_SPCTL_PASS="0")
        self.assertEqual(self.result(proc)[0], 0)
        events = (run / "events").read_text()
        self.assertIn("spctl --assess --type execute ", events)
        self.assertIn("xattr -dr com.apple.quarantine ", events)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()

    def test_uppercase_checksum_env_var_is_accepted(self):
        Path(str(self.dmg) + ".sha256").unlink()
        expected = hashlib.sha256(self.dmg.read_bytes()).hexdigest().upper()
        proc, run = self.start("uppercase-checksum", CHECKSUM=expected)
        self.assertEqual(self.result(proc)[0], 0)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()

    def test_malformed_checksum_sidecar_is_rejected(self):
        Path(str(self.dmg) + ".sha256").write_text("not-a-valid-sha256  Transnote.dmg\n")
        proc, run = self.start("malformed-checksum")
        self.assertNotEqual(self.result(proc)[0], 0)
        self.assert_no_install(run)
        self.assertIn("SHA256 チェックサムが一致しません", (run / "events").read_text())
        self.assertEqual((self.target / "marker").read_text(), "old")
        self.assert_clean()

    def test_exact_mount_point_ignores_prefix_collision_and_metadata(self):
        other_dmg = self.work / "Other.dmg"
        other_dmg.write_bytes(b"other unrelated dmg")
        # Other DMG has a matching sidecar, so selecting it would bypass Transnote.dmg verification.
        Path(str(other_dmg) + ".sha256").write_text(
            hashlib.sha256(other_dmg.read_bytes()).hexdigest()
        )
        # Verify exact mount point selects Transnote.dmg over an earlier prefix-matching DMG.
        hdiutil_info = "\n".join([
            "================================================",
            f"image-path      : {other_dmg}",
            f"image-alias     : {self.volume}/alias.dmg",
            f"/dev/disk4s1\tApple_HFS\t{self.volume} 1",
            "================================================",
            f"image-path      : {self.dmg}",
            f"/dev/disk5s1\tApple_HFS\t{self.volume}",
            "",
        ])
        proc, run = self.start("exact-mount-ok", MOCK_HDIUTIL_INFO=hdiutil_info)
        code, output = self.result(proc)
        self.assertEqual(code, 0, output)
        events = (run / "events").read_text()
        self.assertIn(f"shasum -a 256 {self.dmg}", events)
        self.assertNotIn(str(other_dmg), events)
        self.assertIn(f"hdiutil detach {self.volume} -quiet", events)
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()

        # Verify a prefix-only mount point without an exact match fails instead of selecting Other.dmg.
        hdiutil_prefix_only = "\n".join([
            "================================================",
            f"image-path      : {other_dmg}",
            f"image-alias     : {self.volume}/alias.dmg",
            f"/dev/disk4s1\tApple_HFS\t{self.volume} 1",
            "",
        ])
        proc_fail, run_fail = self.start("exact-mount-miss", MOCK_HDIUTIL_INFO=hdiutil_prefix_only)
        code_fail, _ = self.result(proc_fail)
        self.assertNotEqual(code_fail, 0)
        self.assert_no_install(run_fail)
        self.assertIn("マウント中の DMG パスを取得できませんでした", (run_fail / "events").read_text())
        self.assertNotIn(str(other_dmg), (run_fail / "events").read_text())
        self.assert_clean()

        # Verify mount-point key format rejects prefix match and selects exact volume.
        hdiutil_mount_point_info = "\n".join([
            f"image-path : {other_dmg}",
            f"mount-point : {self.volume} 1",
            f"image-path : {self.dmg}",
            f"mount-point : {self.volume}",
            "",
        ])
        proc2, run2 = self.start("exact-mount-key", MOCK_HDIUTIL_INFO=hdiutil_mount_point_info)
        code2, output2 = self.result(proc2)
        self.assertEqual(code2, 0, output2)
        events2 = (run2 / "events").read_text()
        self.assertIn(f"shasum -a 256 {self.dmg}", events2)
        self.assertNotIn(str(other_dmg), events2)
        self.assert_clean()

    def test_detach_failure_emits_warning_to_stderr(self):
        proc, run = self.start("detach-fail", MOCK_DETACH_FAIL="1")
        code, output = self.result(proc)
        self.assertEqual(code, 0, output)
        self.assertIn("Warning:", output)
        self.assertIn(str(self.volume), output)
        self.assertIn(f"hdiutil detach {self.volume} -quiet", (run / "events").read_text())
        self.assertEqual((self.target / "marker").read_text(), "new")
        self.assert_clean()


if __name__ == "__main__":
    unittest.main(verbosity=2)
