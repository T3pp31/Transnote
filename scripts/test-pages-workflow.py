#!/usr/bin/env python3
"""Pages デプロイがサイトJSテストの成功を前提にすることを検証する。"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/pages.yml").read_text(encoding="utf-8")


class PagesWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.steps = re.split(r"(?m)^      - ", WORKFLOW)[1:]
        cls.names = [step.splitlines()[0].removeprefix("name: ") for step in cls.steps]

    def test_site_javascript_tests_run_before_artifact_upload(self):
        test_index = next(
            (i for i, step in enumerate(self.steps) if "node app.test.js" in step),
            None,
        )
        self.assertIsNotNone(test_index, "site/app.test.js を実行するステップが必要")
        upload_index = next(
            (i for i, step in enumerate(self.steps) if "actions/upload-pages-artifact@" in step),
            None,
        )
        self.assertIsNotNone(upload_index, "upload-pages-artifact ステップが必要")
        self.assertLess(test_index, upload_index, "テストは artifact アップロードより前に実行すること")

    def test_site_javascript_tests_run_before_deploy(self):
        test_index = next(i for i, step in enumerate(self.steps) if "node app.test.js" in step)
        deploy_index = next(
            (i for i, step in enumerate(self.steps) if "actions/deploy-pages@" in step),
            None,
        )
        self.assertIsNotNone(deploy_index, "deploy-pages ステップが必要")
        self.assertLess(test_index, deploy_index, "テストはデプロイより前に実行すること")

    def test_node_is_available_for_the_test_step(self):
        setup_index = next(
            (i for i, step in enumerate(self.steps) if "actions/setup-node@" in step),
            None,
        )
        test_index = next(i for i, step in enumerate(self.steps) if "node app.test.js" in step)
        self.assertIsNotNone(setup_index, "setup-node ステップが必要")
        self.assertLess(setup_index, test_index)

    def test_deploy_step_is_not_optional(self):
        deploy_index = next(
            i for i, step in enumerate(self.steps) if "actions/deploy-pages@" in step
        )
        self.assertNotRegex(self.steps[deploy_index], r"(?m)^        (if|continue-on-error):")


if __name__ == "__main__":
    unittest.main()
