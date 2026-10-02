"""Configuration contracts: preservation, mode switching, failure, and launch scope."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("agent_mode", str(ROOT / "scripts/a_c_agent_mode"))
spec = importlib.util.spec_from_loader(loader.name, loader)
mode = importlib.util.module_from_spec(spec)
loader.exec_module(mode)


class AgentModes(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        for context in [
            patch.object(mode.Path, "home", return_value=self.home),
            patch.dict(os.environ, {"CODEX_HOME": str(self.home / ".codex"), "CLAUDE_CONFIG_DIR": str(self.home / ".claude"), "A_AGENT_MODE": ""}),
            patch.object(mode.shutil, "which", return_value="/mock/provider"),
            patch.object(mode.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '--approve-for-me choices: "auto"', "")),
        ]:
            context.start()
            self.addCleanup(context.stop)

    def invoke(self, *args):
        output = io.StringIO()
        with patch.object(sys, "argv", ["a_c_agent_mode", *args]), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            mode.main()
        return output.getvalue()

    def put(self, path, text):
        target = self.home / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def test_codex_preserves_user_settings_and_comments(self):
        config = self.put(".codex/config.toml", '''# my model
model = "custom-model"
developer_instructions = """Keep this literal:
approval_policy = 'not a setting'
"""
[sandbox_workspace_write]
writable_roots = ["/tmp/build-cache"]
[mcp_servers.local]
command = "local-server"
[projects."/tmp/project"]
trust_level = "trusted"
''')
        before = tomllib.loads(config.read_text())
        self.invoke("install", "--provider", "codex", "--mode", "agentic")
        after = tomllib.loads(config.read_text())
        for key in ["model", "developer_instructions", "mcp_servers", "projects"]:
            self.assertEqual(before[key], after[key])
        self.assertIn("# my model", config.read_text())
        self.assertEqual(after["sandbox_workspace_write"]["writable_roots"], ["/tmp/build-cache"])
        self.assertEqual(after["approvals_reviewer"], "auto_review")
        self.assertTrue(after["sandbox_workspace_write"]["network_access"])
        self.assertEqual(len(list(config.parent.glob("config.toml.before-mode-*"))), 1)

    def test_reinstall_idempotent_and_switch_modes(self):
        for selected in ("agentic", "interactive", "auto"):
            self.invoke("install", "--provider", "codex", "--mode", selected)
            files = {p: p.read_bytes() for p in self.home.rglob("*") if p.is_file()}
            self.invoke("install", "--provider", "codex", "--mode", selected)
            self.assertEqual(files, {p: p.read_bytes() for p in self.home.rglob("*") if p.is_file()})
            data = tomllib.loads((self.home / ".codex/config.toml").read_text())
            for key, value in mode.MODES[selected]["codex"].items():
                self.assertEqual(mode.nested_get(data, key.split(".")), value)

    def test_toml_layouts_and_multiline_arrays(self):
        layouts = [
            'sandbox_workspace_write.writable_roots = [\n"/tmp/cache",\n]\n',
            '["sandbox_workspace_write"] # own cache\nwritable_roots = []\n',
            'approval_policy = {granular = {sandbox_approval = true}}\n',
            '[[other.entries]]\nname = "a"\n[[other.entries]]\nname = "b"\n',
        ]
        for text in layouts:
            with self.subTest(text=text):
                rendered = mode.patch_toml(text, mode.MODES["agentic"]["codex"])
                self.assertEqual(rendered, mode.patch_toml(rendered, mode.MODES["agentic"]["codex"]))

    def test_refuses_mixed_inline_table_without_writing(self):
        config = self.put(".codex/config.toml", 'sandbox_workspace_write = {network_access = false, writable_roots = []}\n')
        before = config.read_bytes()
        with self.assertRaises(ValueError):
            self.invoke("install", "--provider", "codex", "--mode", "agentic")
        self.assertEqual(config.read_bytes(), before)

    def test_dry_run_creates_nothing(self):
        self.invoke("install", "--mode", "agentic", "--dry-run")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_json_merge_keeps_permissions_hooks_and_models(self):
        config = self.put(".claude/settings.json", json.dumps({"permissions": {"deny": ["Bash(rm *)"]}, "hooks": {"Stop": []}, "model": "custom"}))
        self.invoke("install", "--provider", "claude", "--mode", "agentic")
        data = json.loads(config.read_text())
        self.assertEqual(data["permissions"], {"deny": ["Bash(rm *)"], "defaultMode": "auto"})
        self.assertEqual(data["model"], "custom")
        self.assertEqual(data["hooks"], {"Stop": []})

    def test_guidance_preserves_managed_memory_and_personal_text(self):
        old = "personal notes\n<!-- >>> agentic-devkit: managed memory >>> -->\nexisting memory\n<!-- <<< agentic-devkit: managed memory <<< -->\n"
        path = self.put(".codex/AGENTS.md", old)
        self.invoke("install", "--provider", "codex", "--mode", "interactive")
        self.assertTrue(path.read_text().startswith(old))
        self.assertEqual(path.read_text().count(mode.BEGIN), 1)

    def test_malformed_second_provider_aborts_before_first_write(self):
        self.put(".claude/settings.json", "invalid json")
        with self.assertRaises(ValueError):
            self.invoke("install", "--mode", "interactive")
        self.assertFalse((self.home / ".codex").exists())

    def test_symlink_refused(self):
        source = self.put("original", "")
        (self.home / ".codex").mkdir()
        (self.home / ".codex/config.toml").symlink_to(source)
        with self.assertRaises(ValueError):
            self.invoke("install", "--provider", "codex", "--mode", "interactive")
        self.assertEqual(source.read_text(), "")

    def test_writable_roots_are_explicit_additive_and_deduplicated(self):
        config = self.put(".codex/config.toml", '[sandbox_workspace_write]\nwritable_roots = ["/tmp/existing"]\n')
        self.invoke("install", "--provider", "codex", "--mode", "agentic", "--writable-root", str(self.home), "--writable-root", str(self.home))
        data = tomllib.loads(config.read_text())
        self.assertEqual(data["sandbox_workspace_write"]["writable_roots"], ["/tmp/existing", str(self.home.resolve())])

    def test_status_reports_project_candidates_without_secrets(self):
        self.put(".codex/config.toml", 'model = "PRIVATE_VALUE"\napproval_policy = "on-request"\n')
        self.put("project/.codex/config.toml", 'approval_policy = "never"\n')
        output = self.invoke("status", "--provider", "codex", "--project", str(self.home / "project"))
        self.assertIn("potential project override:", output)
        self.assertIn("Active permissions not confirmed", output)
        self.assertNotIn("PRIVATE_VALUE", output)

    def test_provider_limitations_explicit(self):
        with self.assertRaisesRegex(ValueError, "no supported mapping"):
            self.invoke("install", "--provider", "gemini-cli", "--mode", "auto")
        output = self.invoke("install", "--provider", "gemini-cli", "--mode", "agentic")
        self.assertIn("still asks", output)
        data = json.loads((self.home / ".gemini/settings.json").read_text())
        self.assertEqual(data["general"]["defaultApprovalMode"], "auto_edit")

    def test_old_provider_cannot_silently_degrade(self):
        with patch.object(mode.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "old help", "")):
            for provider in ("codex", "claude"):
                with self.subTest(provider=provider), self.assertRaisesRegex(ValueError, "does not advertise"):
                    self.invoke("install", "--provider", provider, "--mode", "agentic")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_run_sets_flags_without_persisting_and_preserves_arguments(self):
        with patch.object(mode.os, "execvp") as execute, patch.object(mode.os, "chdir") as chdir:
            self.invoke("run", "--provider", "codex", "--mode", "agentic", "--project", str(self.home), "--", "task with spaces")
            arguments = execute.call_args.args[1]
            self.assertIn('approvals_reviewer="auto_review"', arguments)
            self.assertEqual(arguments[-1], "task with spaces")
            chdir.assert_called_once_with(self.home)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_auto_run_requires_headless_task(self):
        for provider in ("codex", "claude"):
            with self.subTest(provider=provider), self.assertRaises(SystemExit):
                self.invoke("run", "--provider", provider, "--mode", "auto", "--dry-run")
        output = self.invoke("run", "--provider", "codex", "--mode", "auto", "--dry-run", "--", "exec", "test")
        self.assertIn("never", output)
        self.assertIn("exec test", output)

    def test_selection_required_and_environment_default(self):
        with self.assertRaises(SystemExit):
            self.invoke("install", "--provider", "codex")
        with patch.dict(os.environ, {"A_AGENT_MODE": "interactive"}):
            self.invoke("install", "--provider", "codex")
        self.assertTrue((self.home / ".codex/config.toml").exists())

    def test_claude_task_mode_resolver(self):
        self.assertEqual(self.invoke("resolve", "--provider", "claude", "--mode", "interactive").strip(), "default")
        self.assertEqual(self.invoke("resolve", "--provider", "claude", "--mode", "auto").strip(), "dontAsk")


if __name__ == "__main__":
    unittest.main()
