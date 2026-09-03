# The root repo, and the contract this devkit reads

A **root repo** is one small repository per organisation that owns two things this devkit does
not: the paths on a machine, and the rules that outlive any toolkit. It is optional. Without one,
every part of this devkit still works standalone.

With one, the dependency points the right way. This devkit reads the root repo; the root repo
never reads this devkit. That is what makes the toolkit swappable: replace it and you change a
handful of values, not a single rule.

## Why it is the first repo you create somewhere new

Everything else is named inside it. The brains, the overlays, the framework, the repo tiers, this
devkit itself. A machine only has to learn one path by hand, and it resolves the rest.

Create one with:

```bash
a_c_root_init ~/work/<name> --org "Acme"
```

That copies `templates/root-repo`, which is a starter, not a dependency. Once copied, the files
are that company's own: edit them freely, this devkit never reads their prose.

## The contract

Set `A_ROOT_DIR` in the shell to the root repo. `shell/bootstrap.profile` sources
`$A_ROOT_DIR/root.config`, then `root.local.config` on top, then maps the keys below to the
variable names this devkit's scripts already use.

### Required

| Key | Used for |
|---|---|
| `DEVKIT_DIR` | becomes `MY_WORKFLOW_DIR`: this repo. Everything else on PATH follows from it |

### Repo tiers

| Key | Becomes | Used for |
|---|---|---|
| `ROOT_BASE_DIR` | nothing directly | the one value most machines override; the tiers derive from it |
| `ORG_REPOS_DIR` | `a_dir_w_repos` | the `cd_w` alias |
| `PERSONAL_REPOS_DIR` | `a_dir_p_repos` | the `cd_p` alias |
| `GLOBAL_REPOS_DIR` | `a_dir_g_repos` | the `cd_g` alias |

### Roles the generated guidance renders

| Key | Becomes | What it contributes |
|---|---|---|
| `ORG_BRAIN_DIR` | `A_AGENT_ORG_BRAIN_DIR` | a section naming the shared brain and telling the agent to read it before guessing at a name |
| `PRIVATE_BRAIN_DIR` | `A_AGENT_BRAIN_DIR` | the same for a personal brain |
| `ORG_DEVKIT_DIR` | `A_AGENT_ORG_OVERLAY_DIR` | `machine/<MACHINE_NAME>.md`, `machine/rules.md`, `machine/glossary.md` from the org overlay |
| `PRIVATE_DEVKIT_DIR` | `A_AGENT_OVERLAY_DIR` | the same three files from the private overlay |
| `A_ROOT_DIR` itself | | an import of `ROOT.md` at the top of the region, and the pointer table is skipped because the root repo owns it |

### Machine values

| Key | Becomes | Used for |
|---|---|---|
| `MACHINE_NAME` | `A_MACHINE_NAME` | selects `machine/<name>.md` in an overlay |
| `MACHINE_TYPE` | `a_machine_type` | with `ORG_SLUG`, selects `<slug>.<type>.profile` in the org overlay |
| `ORG_SLUG` | `a_company_name` | the same |
| `GDRIVE_DIR`, `GDRIVE_CHATS_DIR` | `a_dir_gd`, `a_dir_gc` | the `cd_gd` and `cd_gc` aliases |

Machine values belong in `root.local.config`, which is gitignored, so one machine's values never
land in the repo.

### Conventions on every role

| Suffix | Means |
|---|---|
| `_DIR` | absolute path. **Empty means the repo is not on this machine**, which is a normal state, not an error. Skip it |
| `_ENTRY` | the file to read first in that repo |
| `_REMOTE` | the clone URL. Use the right ssh host alias per account, or a clone authenticates as the wrong identity |
| `_NO_ORG_CONTENT` | company content must never enter this repo. This flag, not `_IS_PUBLIC`, is what a leak check reads: a private repo can still be the wrong home |

## Wiring a machine

One file stays outside git, because something has to know where the root repo is. Four lines:

```zsh
export A_ROOT_DIR="/path/to/the/root/repo"
if [ -f "$A_ROOT_DIR/root.config" ]; then
    # local FIRST: every key in root.config is ${KEY:-default}, so a value set here survives
    # and the paths derived from it follow. The other order expands them before the override.
    [ -f "$A_ROOT_DIR/root.local.config" ] && source "$A_ROOT_DIR/root.local.config"
    source "$A_ROOT_DIR/root.config"
    source "${DEVKIT_DIR}/shell/bootstrap.profile"
fi
```

Put that in the file your shell rc already sources. Everything else is in git. `a_sk_setup_agents`
does this and the rest of the machine setup.

**Then check what the shell sources after it.** Anything that redefines the same alias later
silently wins, and the failure is slow to find because every variable still reads correctly while
the alias is wrong.

## Without a root repo

`A_ROOT_DIR` unset is fully supported. `shell/configs.profile.sample` has a standalone mode where
you set the values by hand, and `memory/core-rules-standalone.md` renders the rules a root repo
would otherwise own. Nothing here requires one.
