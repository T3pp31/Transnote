#!/usr/bin/env python3
"""Release workflow signing regression tests without macOS or real credentials."""

import itertools
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent

MOCKS = """
security() {
  local command="$1"
  printf '%s\\n' "$command" >> "$MOCK_LOG"
  if [[ "$command" == set-key-partition-list ]]; then
    shift
    [[ $# -eq 6 && "$1" == -S && "$2" == apple-tool:,apple:,codesign: &&
       "$3" == -s && "$4" == -k && "$5" == "$CERTIFICATE_PASSWORD" &&
       "$6" == "$RUNNER_TEMP/$EXPECTED_KEYCHAIN_NAME" ]] || exit 2
    grep -qx import "$MOCK_LOG" || exit 3
  fi
  [[ "$command" != "$MOCK_FAIL" ]] || exit 9
}
mock_codesign() {
  grep -qx set-key-partition-list "$MOCK_LOG" || exit 4
  printf 'codesign\\n' >> "$MOCK_LOG"
  if [[ "$1" == -d ]]; then
    printf '<key>com.apple.security.app-sandbox</key><true/>\\n'
  fi
}
"""


def env_values(block, indent):
    # Read only the workflow's single-line env mappings; no YAML dependency needed.
    match = re.search(
        rf"(?m)^{' ' * indent}env:\n((?:{' ' * (indent + 2)}[^\n]+\n)+)", block
    )
    if not match:
        return {}
    return dict(
        line.strip().split(": ", 1)
        for line in match[1].splitlines()
        if not line.lstrip().startswith("#")
    )


def condition_value(expression, **contexts):
    # Only the comparison/conjunction subset used by these gates is supported.
    match = re.fullmatch(r"\$\{\{ (.+) \}\}", expression)
    if not match:
        raise AssertionError(f"Unsupported condition: {expression}")
    results = []
    for term in match[1].split(" && "):
        comparison = re.fullmatch(r"(secrets|env)\.([A-Z_]+) (==|!=) '([^']*)'", term)
        if not comparison:
            raise AssertionError(f"Unsupported condition term: {term}")
        scope, key, operator, expected = comparison.groups()
        equal = contexts[scope].get(key, "") == expected
        results.append(equal if operator == "==" else not equal)
    return all(results)


class ReleaseSecretScopeTests(unittest.TestCase):
    FLAGS = {
        "HAS_SIGNING_SECRETS": (
            "MACOS_CERTIFICATE", "MACOS_CERTIFICATE_PWD", "MACOS_CERTIFICATE_IDENTITY",
        ),
        "HAS_NOTARIZATION_SECRETS": ("APPLE_ID", "APPLE_ID_PASSWORD", "APPLE_TEAM_ID"),
    }
    CONSUMERS = {
        "name: Sign app with Developer ID": {
            "CERTIFICATE_BASE64": "MACOS_CERTIFICATE",
            "CERTIFICATE_PASSWORD": "MACOS_CERTIFICATE_PWD",
            "CERTIFICATE_IDENTITY": "MACOS_CERTIFICATE_IDENTITY",
        },
        "name: Notarize app": {
            "APPLE_ID": "APPLE_ID",
            "APPLE_ID_PASSWORD": "APPLE_ID_PASSWORD",
            "APPLE_TEAM_ID": "APPLE_TEAM_ID",
        },
        "name: Sign DMG with Developer ID": {
            "CERTIFICATE_BASE64": "MACOS_CERTIFICATE",
            "CERTIFICATE_PASSWORD": "MACOS_CERTIFICATE_PWD",
            "CERTIFICATE_IDENTITY": "MACOS_CERTIFICATE_IDENTITY",
        },
        "name: Notarize DMG": {
            "APPLE_ID": "APPLE_ID",
            "APPLE_ID_PASSWORD": "APPLE_ID_PASSWORD",
            "APPLE_TEAM_ID": "APPLE_TEAM_ID",
        },
    }

    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        cls.header, *steps = re.split(r"^      - (?=name: |uses: )", workflow, flags=re.MULTILINE)
        cls.steps = {step.splitlines()[0]: step for step in steps}
        cls.job_env = env_values(cls.header, 4)

    def test_shared_scopes_expose_only_boolean_presence_flags(self):
        remaining = self.header
        for flag, names in self.FLAGS.items():
            expression = "${{ " + " && ".join(f"secrets.{name} != ''" for name in names) + " }}"
            self.assertEqual(self.job_env.get(flag), expression)
            remaining = remaining.replace(f"      {flag}: {expression}\n", "", 1)
        # Also catches secret references in workflow-wide env or other job fields.
        self.assertNotIn("secrets.", remaining)

    def test_raw_secrets_are_only_in_the_consuming_steps_env(self):
        for name in self.CONSUMERS:
            self.assertIn(name, self.steps)
        for name, step in self.steps.items():
            with self.subTest(step=name):
                values = env_values(step, 8)
                remaining = step
                for variable, secret in self.CONSUMERS.get(name, {}).items():
                    expression = "${{ secrets." + secret + " }}"
                    self.assertEqual(values.get(variable), expression)
                    remaining = remaining.replace(f"          {variable}: {expression}\n", "", 1)
                # Includes tests, archive, export, SBOM, DMG and third-party actions.
                self.assertNotIn("secrets.", remaining)

    def test_gates_preserve_unsigned_signed_and_notarized_paths(self):
        gates = []
        for name in self.CONSUMERS:
            match = re.search(r"(?m)^        if: (.+)$", self.steps[name])
            self.assertIsNotNone(match)
            gates.append(match[1])
        for flag in self.FLAGS:
            self.assertIn(flag, self.job_env)
        flags = {flag: self.job_env[flag] for flag in self.FLAGS}
        secret_names = [name for names in self.FLAGS.values() for name in names]
        # All 64 complete/missing/partial configurations, with and without signing success.
        for present in itertools.product((False, True), repeat=len(secret_names)):
            secrets = {
                name: "dummy-value" if exists else ""
                for name, exists in zip(secret_names, present)
            }
            env = {
                flag: str(condition_value(value, secrets=secrets)).lower()
                for flag, value in flags.items()
            }
            can_sign = all(secrets[name] for name in self.FLAGS["HAS_SIGNING_SECRETS"])
            can_notarize = all(secrets[name] for name in self.FLAGS["HAS_NOTARIZATION_SECRETS"])
            for signed in ("", "0", "1"):
                with self.subTest(present=present, signed=signed):
                    env["SIGNED"] = signed
                    self.assertEqual(condition_value(gates[0], env=env), can_sign)
                    self.assertEqual(
                        condition_value(gates[1], env=env), can_notarize and signed == "1"
                    )
                    self.assertEqual(
                        condition_value(gates[2], env=env), can_sign and signed == "1"
                    )
                    self.assertEqual(
                        condition_value(gates[3], env=env), can_notarize and signed == "1"
                    )

    def test_dmg_signing_and_notarization_precede_checksum_and_attestation(self):
        step_names = list(self.steps.keys())
        dmg_index = step_names.index("name: Create DMG")
        sign_dmg_index = step_names.index("name: Sign DMG with Developer ID")
        notarize_dmg_index = step_names.index("name: Notarize DMG")
        checksum_index = step_names.index("name: Compute SHA256 checksums")
        attest_index = step_names.index("name: Attest build provenance")
        self.assertLess(dmg_index, sign_dmg_index)
        self.assertLess(sign_dmg_index, notarize_dmg_index)
        self.assertLess(notarize_dmg_index, checksum_index)
        self.assertLess(checksum_index, attest_index)

    def test_signing_steps_delegate_keychain_setup_to_shared_script(self):
        for name in ("name: Sign app with Developer ID", "name: Sign DMG with Developer ID"):
            with self.subTest(step=name):
                step = self.steps[name]
                self.assertIn("source ./scripts/release-signing-keychain.sh", step)
                self.assertIn("setup_signing_keychain", step)
                self.assertIn("cleanup_signing_keychain", step)
                self.assertNotIn("security create-keychain", step)

    def test_notarize_app_validates_stapler_and_gatekeeper_before_marking_notarized(self):
        step = self.steps["name: Notarize app"]
        staple_pos = step.index('xcrun stapler staple "$APP_PATH"')
        validate_pos = step.index('xcrun stapler validate "$APP_PATH"')
        spctl_pos = step.index('spctl --assess --type execute --verbose=4 "$APP_PATH"')
        env_pos = step.index('echo "NOTARIZED=1" >> "$GITHUB_ENV"')
        self.assertLess(staple_pos, validate_pos)
        self.assertLess(validate_pos, spctl_pos)
        self.assertLess(spctl_pos, env_pos)


class AppEntitlementsTests(unittest.TestCase):
    def test_sandboxed_app_has_app_scoped_bookmark_entitlement(self):
        with (ROOT / "LocalTranscriber/LocalTranscriber.entitlements").open("rb") as source:
            entitlements = plistlib.load(source)

        # relativeTo: nil の .withSecurityScope はアプリスコープを使用する。
        # サンドボックスやユーザー選択ファイルへのアクセスも維持する。
        for key in (
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.files.bookmarks.app-scope",
        ):
            with self.subTest(entitlement=key):
                self.assertIs(entitlements.get(key), True, f"{key} must be boolean true")


class ReleaseSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Sign app with Developer ID\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        cls.script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        # Substitute only the runner expressions and absolute executable path;
        # keep the actual workflow's commands and error handling under test.
        for expression, variable in (
            ("env.RELEASE_APP_DIR", "RELEASE_APP_DIR"),
            ("env.APP_NAME", "APP_NAME"),
            ("github.workspace", "GITHUB_WORKSPACE"),
        ):
            cls.script = cls.script.replace("${{ " + expression + " }}", "$" + variable)
        if "${{" in cls.script:
            raise AssertionError("Unhandled workflow expression in signing step")
        cls.script, count = re.subn(
            r"(?m)^/usr/bin/codesign(?= )", "mock_codesign", cls.script
        )
        if count != 3:
            raise AssertionError("Expected signing, verification, and entitlement inspection commands")

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="release signing ")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.log = self.root / "events"
        self.github_env = self.root / "github-env"

    def run_step(self, fail_command=""):
        self.log.write_text("")
        self.github_env.write_text("")
        env = dict(
            os.environ,
            RUNNER_TEMP=str(self.root),
            EXPECTED_KEYCHAIN_NAME="app-signing.keychain-db",
            CERTIFICATE_BASE64="ZHVtbXk=",  # dummy, not a real certificate
            CERTIFICATE_PASSWORD="dummy password with spaces",
            CERTIFICATE_IDENTITY="Developer ID Application: Test",
            RELEASE_APP_DIR=str(self.root / "release app"),
            APP_NAME="Transnote",
            GITHUB_WORKSPACE=str(ROOT),
            GITHUB_ENV=str(self.github_env),
            MOCK_LOG=str(self.log),
            MOCK_FAIL=fail_command,
        )
        return subprocess.run(
            ["bash", "-c", MOCKS + self.script], cwd=ROOT, env=env, capture_output=True, text=True
        )

    def test_partition_list_is_set_after_import_and_before_signing(self):
        result = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [
                "create-keychain", "set-keychain-settings", "unlock-keychain",
                "import", "set-key-partition-list", "list-keychain",
                "codesign", "codesign", "codesign",
                "delete-keychain",
            ],
        )
        self.assertEqual(self.github_env.read_text(), "SIGNED=1\n")

    def test_certificate_file_is_removed_after_signing(self):
        result = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "certificate.p12").exists())

    def test_keychain_is_destroyed_even_when_signing_fails(self):
        for command in ("import", "set-key-partition-list", "list-keychain"):
            with self.subTest(command=command):
                result = self.run_step(fail_command=command)
                self.assertEqual(result.returncode, 9, result.stderr)
                events = self.log.read_text().splitlines()
                self.assertEqual(events[-1], "delete-keychain")
                self.assertFalse((self.root / "certificate.p12").exists())

    def test_keychain_failures_stop_before_signing(self):
        for command in ("import", "set-key-partition-list"):
            with self.subTest(command=command):
                result = self.run_step(fail_command=command)
                self.assertEqual(result.returncode, 9, result.stderr)
                events = self.log.read_text().splitlines()
                self.assertEqual(events[-2:], [command, "delete-keychain"])
                self.assertNotIn("codesign", events)
                self.assertEqual(self.github_env.read_text(), "")


class ReleaseDMGSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Sign DMG with Developer ID\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        cls.script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        if "${{" in cls.script:
            raise AssertionError("Unhandled workflow expression in DMG signing step")
        cls.script, count = re.subn(
            r"(?m)^/usr/bin/codesign(?= )", "mock_codesign", cls.script
        )
        if count != 2:
            raise AssertionError("Expected DMG signing and verification commands")

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="release dmg signing ")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.log = self.root / "events"
        self.versioned_dmg = self.root / "Transnote-1.0.0.dmg"
        self.latest_dmg = self.root / "Transnote.dmg"
        self.versioned_dmg.write_bytes(b"signed dmg bytes")

    def run_step(self, fail_command=""):
        self.log.write_text("")
        env = dict(
            os.environ,
            RUNNER_TEMP=str(self.root),
            EXPECTED_KEYCHAIN_NAME="dmg-signing.keychain-db",
            CERTIFICATE_BASE64="ZHVtbXk=",
            CERTIFICATE_PASSWORD="dummy password with spaces",
            CERTIFICATE_IDENTITY="Developer ID Application: Test",
            VERSIONED_DMG=str(self.versioned_dmg),
            LATEST_DMG=str(self.latest_dmg),
            MOCK_LOG=str(self.log),
            MOCK_FAIL=fail_command,
        )
        return subprocess.run(
            ["bash", "-c", MOCKS + self.script], cwd=ROOT, env=env, capture_output=True, text=True
        )

    def test_dmg_signing_verifies_copies_latest_and_cleans_up_keychain(self):
        result = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [
                "create-keychain", "set-keychain-settings", "unlock-keychain",
                "import", "set-key-partition-list", "list-keychain",
                "codesign", "codesign",
                "delete-keychain",
            ],
        )
        self.assertEqual(self.latest_dmg.read_bytes(), b"signed dmg bytes")
        self.assertFalse((self.root / "dmg-certificate.p12").exists())

    def test_dmg_signing_cleans_up_keychain_on_failure(self):
        result = self.run_step(fail_command="import")
        self.assertEqual(result.returncode, 9, result.stderr)
        events = self.log.read_text().splitlines()
        self.assertEqual(events[-2:], ["import", "delete-keychain"])
        self.assertNotIn("codesign", events)
        self.assertFalse((self.root / "dmg-certificate.p12").exists())


if __name__ == "__main__":
    unittest.main()
