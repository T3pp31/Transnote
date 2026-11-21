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
        # on.push.paths などのリスト項目を混入させないよう、deploy ジョブの steps に限定する。
        jobs = WORKFLOW.split("\njobs:\n", 1)
        if len(jobs) != 2 or "\n  deploy:\n" not in "\n" + jobs[1]:
            raise AssertionError("deploy ジョブが見つからない")
        deploy = ("\n" + jobs[1]).split("\n  deploy:\n", 1)[1]
        deploy = re.split(r"(?m)^  \S", deploy, maxsplit=1)[0]
        if "\n    steps:\n" not in deploy:
            raise AssertionError("deploy ジョブの steps が見つからない")
        cls.steps = re.split(r"(?m)^      - ", deploy.split("\n    steps:\n", 1)[1])[1:]

    def step_index(self, marker, description):
        index = next((i for i, step in enumerate(self.steps) if marker in step), None)
        self.assertIsNotNone(index, f"{description} ステップが deploy ジョブに必要")
        return index

    def test_site_javascript_tests_run_before_artifact_upload(self):
        test_index = self.step_index("node app.test.js", "site/app.test.js を実行する")
        upload_index = self.step_index("actions/upload-pages-artifact@", "upload-pages-artifact")
        self.assertLess(test_index, upload_index, "テストは artifact アップロードより前に実行すること")

    def test_site_javascript_tests_run_before_deploy(self):
        test_index = self.step_index("node app.test.js", "site/app.test.js を実行する")
        deploy_index = self.step_index("actions/deploy-pages@", "deploy-pages")
        self.assertLess(test_index, deploy_index, "テストはデプロイより前に実行すること")

    def test_node_is_available_for_the_test_step(self):
        setup_index = self.step_index("actions/setup-node@", "setup-node")
        test_index = self.step_index("node app.test.js", "site/app.test.js を実行する")
        self.assertLess(setup_index, test_index)

    def test_site_javascript_test_failures_stop_the_job(self):
        step = self.steps[self.step_index("node app.test.js", "site/app.test.js を実行する")]
        self.assertNotRegex(step, r"(?m)^        (if|continue-on-error):")
        run = step.split("        run: |\n", 1)
        self.assertEqual(len(run), 2, "テストステップは run ブロックで実行すること")
        commands = [line.strip() for line in run[1].splitlines() if line.strip()]
        # 終了コードを握りつぶす変更（|| true など）を検出する。
        self.assertEqual(commands, ["cd site", "node app.test.js"])

    def test_deploy_step_is_not_optional(self):
        step = self.steps[self.step_index("actions/deploy-pages@", "deploy-pages")]
        self.assertNotRegex(step, r"(?m)^        (if|continue-on-error):")


if __name__ == "__main__":
    unittest.main()
