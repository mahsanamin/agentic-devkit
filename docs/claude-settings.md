# Claude Code settings

`~/.claude/settings.json` is built from layers kept in git, so every machine gets the same
setup without copying the file around.

| Layer | File | Holds |
|---|---|---|
| base | `config/claude-settings/settings.json` in this repo | generic defaults for every machine |
| private overlay | `config/claude-settings.json` | personal additions |
| org overlay | `config/claude-settings.json` | company plugins, permissions, auto mode context |
| machine | `machine/<MACHINE_NAME>.claude-settings.json` in either overlay | one machine only |

Later layers win on a single value, and lists are combined. Strings can use `${VAR}` for any
`root.config` value, such as `${DEVKIT_DIR}` or `${ORG_REPOS_DIR}`. If the variable is not set
on a machine, that list entry is left out instead of being written with a broken path.

```sh
a_c_claude_settings diff        # what apply would change
a_c_claude_settings apply       # write it (also run by ./install.sh)
a_c_claude_settings show        # the merged layers only
a_c_claude_settings layers      # which layer files exist here
a_c_claude_settings replicate   # the commands to run on another machine
```

Applying never drops a key the layers do not mention. Permission lists and `autoMode.allow`
are combined with what is already in the file, so a rule you approved locally stays. Other
managed values, including `autoMode.environment`, `statusLine` and each marketplace entry,
replace the local value. The previous file is saved next to it as
`settings.json.before-settings-*`.

Settings only name plugins, they do not install them. So `apply` also registers each managed
marketplace (re-adding one whose source changed) and installs each enabled plugin that is
missing, through the `claude` CLI. A plugin that cannot be installed, for example a company
marketplace on a machine without access to its repo, gives a warning and the rest carries on.
Claude Code then lists it as an error in `/plugin` until it can be installed. Use
`--no-plugins` to write only the settings file.

`./install.sh` applies settings before the agent mode, so `A_AGENT_MODE` still decides
`permissions.defaultMode` when it is set.

To change a setting for every machine, edit the layer, commit, and run `apply`. A one-off
change for one machine belongs in that machine's layer file, or stays local in the file.
