"""Layered Claude settings: layer order, local survival, placeholders, wholesale objects."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("claude_settings", str(ROOT / "scripts/a_c_claude_settings"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cs = importlib.util.module_from_spec(spec)
loader.exec_module(cs)


class ClaudeSettings(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.dir = Path(self.temporary.name)
        self.org = self.dir / "org"
        (self.org / "config").mkdir(parents=True)
        (self.org / "machine").mkdir()
        self.settings = self.dir / "home" / "settings.json"
        self.settings.parent.mkdir()
        env = {"CLAUDE_CONFIG_DIR": str(self.settings.parent)}
        self.enterContext(patch.dict(os.environ, env))
        self.config = {k: "" for k in cs.CONFIG_KEYS}
        self.config.update(DEVKIT_DIR=str(ROOT), ORG_DEVKIT_DIR=str(self.org), MACHINE_NAME="box", HOME="/h")

    def write(self, path, data):
        path.write_text(json.dumps(data))

    def test_org_and_machine_layers_add_to_base(self):
        self.write(self.org / "config/claude-settings.json", {"permissions": {"allow": ["Bash(org:*)"]}})
        self.write(self.org / "machine/box.claude-settings.json", {"permissions": {"deny": ["mcp__x"]}})
        merged = cs.managed(self.config)
        self.assertIn("Bash(grep:*)", merged["permissions"]["allow"])
        self.assertIn("Bash(org:*)", merged["permissions"]["allow"])
        self.assertEqual(merged["permissions"]["deny"], ["mcp__x"])
        self.assertEqual(merged["statusLine"]["command"], f"{ROOT}/scripts/a_c_statusline")

    def test_apply_keeps_local_keys_and_approvals(self):
        self.write(self.settings, {"permissions": {"allow": ["Bash(local:*)"]}, "hooks": {"x": 1},
                                   "autoMode": {"environment": ["stale"]}})
        self.write(self.org / "config/claude-settings.json", {"autoMode": {"environment": ["fresh"]}})
        cs.apply(self.config, dry_run=False)
        result = json.loads(self.settings.read_text())
        self.assertEqual(result["hooks"], {"x": 1})
        self.assertEqual(result["permissions"]["allow"][0], "Bash(local:*)")
        self.assertIn("Bash(grep:*)", result["permissions"]["allow"])
        self.assertEqual(result["autoMode"]["environment"], ["fresh"])
        self.assertTrue(list(self.settings.parent.glob("settings.json.before-settings-*")))
        cs.apply(self.config, dry_run=False)
        self.assertEqual(len(list(self.settings.parent.glob("settings.json.before-settings-*"))), 1)

    def test_marketplace_replaced_whole(self):
        self.write(self.settings, {"extraKnownMarketplaces": {"m": {"source": {"source": "directory", "path": "/old"}}}})
        self.write(self.org / "config/claude-settings.json",
                   {"extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "o/r"}}}})
        cs.apply(self.config, dry_run=False)
        source = json.loads(self.settings.read_text())["extraKnownMarketplaces"]["m"]["source"]
        self.assertEqual(source, {"source": "github", "repo": "o/r"})

    def test_unset_placeholder_drops_entry(self):
        self.write(self.org / "config/claude-settings.json",
                   {"permissions": {"allow": ["Bash(${ORG_REPOS_DIR}/x:*)", "Bash(ok:*)"]}})
        with patch("sys.stderr"):
            allow = cs.managed(self.config)["permissions"]["allow"]
        self.assertIn("Bash(ok:*)", allow)
        self.assertFalse([a for a in allow if "x:*" in a])

    def test_malformed_live_file_is_refused(self):
        self.settings.write_text("{nope")
        with self.assertRaises(ValueError):
            cs.apply(self.config, dry_run=False)

    def test_plugin_preview_never_starts_the_cli(self):
        self.write(self.org / "config/claude-settings.json", {
            "enabledPlugins": {"p@m": True},
            "extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "o/r"}}}})
        with patch.object(cs.shutil, "which", return_value="/bin/claude"), \
                patch.object(cs, "claude_json", side_effect=AssertionError("CLI started during preview")), \
                patch.object(cs, "run_claude") as run:
            cs.sync_plugins(self.config, dry_run=True)
        self.assertFalse((self.settings.parent / "plugins").exists())
        run.assert_any_call(["plugin", "install", "p@m"], True)

    def test_plugin_preview_uses_existing_registry(self):
        self.write(self.org / "config/claude-settings.json", {
            "enabledPlugins": {"p@m": True},
            "extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "o/r"}}}})
        plugins = self.settings.parent / "plugins"
        plugins.mkdir()
        self.write(plugins / "known_marketplaces.json", {"m": {"source": {"source": "github", "repo": "o/r"}}})
        self.write(plugins / "installed_plugins.json", {"plugins": {"p@m": [{}]}})
        with patch.object(cs.shutil, "which", return_value="/bin/claude"), \
                patch.object(cs, "claude_json", side_effect=AssertionError("CLI started during preview")), \
                patch.object(cs, "run_claude") as run:
            cs.sync_plugins(self.config, dry_run=True)
        self.assertNotIn(unittest.mock.call(["plugin", "install", "p@m"], True), run.call_args_list)
        self.assertNotIn(unittest.mock.call(["plugin", "marketplace", "add", "o/r"], True), run.call_args_list)

    def test_plugin_sync_adds_missing_and_changed(self):
        self.write(self.org / "config/claude-settings.json", {
            "enabledPlugins": {"p@m": True, "off@m": False},
            "extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "o/r"}}}})
        lists = {("marketplace", "list"): [{"name": "m", "source": "directory", "path": "/old"}], ("list",): []}
        calls = []
        with patch.object(cs.shutil, "which", return_value="/bin/claude"), \
                patch.object(cs, "claude_json", side_effect=lambda *a: lists[a]), \
                patch.object(cs, "run_claude", side_effect=lambda a, d: calls.append(a[1:])):
            cs.sync_plugins(self.config, dry_run=False)
        self.assertIn(["marketplace", "remove", "m"], calls)
        self.assertIn(["marketplace", "add", "o/r"], calls)
        self.assertIn(["install", "p@m"], calls)
        self.assertNotIn(["install", "off@m"], calls)


if __name__ == "__main__":
    unittest.main()
