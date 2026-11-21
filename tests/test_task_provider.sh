#!/usr/bin/env bash
# Shell integration tests with local Git fixtures and captured CLI stubs, no API calls.
set -euo pipefail
TASK_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" python3 - <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(os.environ['TASK_TEST_ROOT'])
checks = 0

def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1

def write(path, text):
    path.write_text(text)
    path.chmod(0o755)

with tempfile.TemporaryDirectory(prefix='task-provider-', dir=os.environ.get('TMPDIR', '/tmp')) as tmp:
    tmp = Path(tmp)
    for shell in ('bash', 'zsh'):
        if not shutil.which(shell):
            print(f'SKIP: {shell} is not installed')
            continue
        case = tmp / shell
        kit = case / 'kit'
        scripts = kit / 'scripts'
        scripts.mkdir(parents=True)
        for filename in ('a_c_task_start', 'a_c_task_resume', 'a_s_task_common.sh', 'a_s_task_launch', 'a_c_claude_remote', 'a_c_agent_mode'):
            shutil.copy2(source / 'scripts' / filename, scripts / filename)
        shutil.copytree(source / 'config/agent-modes', kit / 'config/agent-modes')
        bindir = case / 'bin'
        bindir.mkdir()
        for provider in ('claude', 'codex'):
            write(bindir / provider, '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--help']:
    print('"auto" "acceptEdits" --approve-for-me'); sys.exit(0)
with open(os.environ['CAPTURE'], 'a') as f:
    f.write(json.dumps({'provider': os.path.basename(sys.argv[0]), 'args': sys.argv[1:], 'cwd': os.getcwd()}) + '\\n')
sys.exit(int(os.environ.get('CLI_EXIT', '0')))
''')
        # Sourceable fixture creates real local worktrees without remote access.
        write(scripts / 'a_g_worktree_init', '''branch="$1"; shift
common="$(git rev-parse --git-common-dir)"
main="$(cd "$(dirname "$common")" && pwd)"
wt="$(dirname "$main")/WorkTrees/$(basename "$main")/${branch//\\//-}"
git worktree add --quiet -b "$branch" "$wt" "$2" || return 1
cd "$wt"
''')
        # Avoid network while exercising every other real Git operation.
        realgit = shutil.which('git')
        write(bindir / 'git', f'''#!/usr/bin/env bash
for arg in "$@"; do [ "$arg" != fetch ] || exit 0; done
exec '{realgit}' "$@"
''')
        capture = case / 'capture.jsonl'
        env = dict(os.environ, PATH=f'{bindir}:' + os.environ['PATH'],
                   HOME=str(case / 'home'), A_TASK_HOME=str(case / 'state'),
                   A_C_WORKFLOW_DIR=str(kit), A_TASK_WT_DIR=str(scripts),
                   CAPTURE=str(capture), A_TASK_BRANCH_TYPE='feature',
                   A_TASK_DEFAULT_KEY='PROJ', A_TASK_ADDR_WAIT='0',
                   A_C_NO_ATTACH='1', A_T_NO_FX='1', NO_COLOR='1')
        for name in ('A_TASK_PROVIDER', 'A_TASK_PERMISSION_MODE', 'A_AGENT_MODE', 'A_JIRA_EMAIL', 'A_JIRA_TOKEN',
                     'ZELLIJ', 'ZELLIJ_SESSION_NAME', 'GIT_DIR', 'GIT_WORK_TREE'):
            env.pop(name, None)
        Path(env['HOME']).mkdir()
        # Global/local hooks and configuration do not affect the disposable fixtures.
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                   GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0='/dev/null')
        repo = case / 'sample repo'
        repo.mkdir()
        def git(*args):
            return subprocess.run([realgit, '-C', str(repo), *args], env=env, check=True,
                                  capture_output=True, text=True).stdout
        git('init', '-q', '-b', 'main')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'fixture')

        def invoke(command, *args, success=True, extra=None):
            runenv = dict(env, **(extra or {}))
            script = scripts / command
            result = subprocess.run([shutil.which(shell), '-c', '. "$1" "${@:2}"', 'fixture', str(script), *map(str, args)],
                                    env=runenv, cwd=repo, capture_output=True, text=True, stdin=subprocess.DEVNULL)
            check((result.returncode == 0) == success,
                  f'{shell} {command} {args}: status {result.returncode}\n{result.stdout}\n{result.stderr}')
            return result
        def calls():
            return [json.loads(line) for line in capture.read_text().splitlines()] if capture.exists() else []
        def last():
            return calls()[-1]
        def start(ticket, *args, **kwargs):
            return invoke('a_c_task_start', '-r', repo, '-t', ticket, '-f', 'login', '-b', 'main', '-y', *args, **kwargs)

        start('PROJ-1', '--provider', 'codex', '-m', 'model with spaces', '-p', 'read `literal` $value')
        check(last()['provider'] == 'codex', f'{shell}: explicit codex')
        check(last()['args'] == ['--sandbox', 'workspace-write', '--ask-for-approval', 'never', '--model',
                                'model with spaces', '--', 'read `literal` $value'], f'{shell}: native argv preserved: {last()}')
        check(last()['cwd'].endswith('/feature-proj-1-login'), f'{shell}: worktree cwd')
        start('PROJ-1', '-c')
        check(last()['provider'] == 'codex', f'{shell}: repeated start preserves provider')
        invoke('a_c_task_resume', 'PROJ-1', '-c', '--', '--model', 'resume-model')
        check(last()['provider'] == 'codex' and last()['args'][-2:] == ['--model', 'resume-model'], f'{shell}: resume native model')
        count = len(calls())
        invoke('a_c_task_resume', 'PROJ-1')
        check(len(calls()) == count, f'{shell}: legacy resume only cds')
        invoke('a_c_task_resume', 'PROJ-1', '--provider', 'claude', '-p', 'inspect diff')
        check(last()['provider'] == 'claude' and '--remote-control' in last()['args'], f'{shell}: explicit resume overrides provider')
        start('PROJ-1', '-c')
        check(last()['provider'] == 'claude', f'{shell}: override saved for start')
        start('PROJ-2', '-c')
        check(last()['provider'] == 'claude' and '--permission-mode' in last()['args'], f'{shell}: default Claude preserved')
        check(last()['args'][1] == 'sample-repo-proj-2-login', f'{shell}: legacy session name')
        # Missing provider metadata in an old six-column registry still launches Claude.
        for metadata in (case / 'state/providers').iterdir():
            metadata.unlink()
        invoke('a_c_task_resume', 'PROJ-2', '-c')
        check(last()['provider'] == 'claude', f'{shell}: legacy registry resume')
        start('PROJ-3', '-c', extra={'A_TASK_PROVIDER': 'codex'})
        check(last()['provider'] == 'codex', f'{shell}: environment provider default')
        start('PROJ-3', '-c', extra={'A_TASK_PROVIDER': 'claude'})
        check(last()['provider'] == 'codex', f'{shell}: saved selection beats env')
        start('PROJ-4', '--provider', 'codex', '--bypass')
        check(last()['args'] == ['--dangerously-bypass-approvals-and-sandbox'], f'{shell}: Codex bypass')
        start('PROJ-4', '--bypass', '--', '--sandbox=read-only', '-a', 'on-request')
        check(last()['args'] == ['--sandbox=read-only', '-a', 'on-request'], f'{shell}: native permission overrides bypass')
        start('PROJ-4', '--', '--sandbox', 'read-only')
        check(last()['args'] == ['--ask-for-approval', 'never', '--sandbox', 'read-only'], f'{shell}: independent sandbox override')
        start('PROJ-4', '-c', extra={'A_AGENT_MODE': 'agentic'})
        check('approvals_reviewer="auto_review"' in last()['args'], f'{shell}: shared Codex permission mapping')
        start('PROJ-4', '-c', extra={'A_AGENT_MODE': 'invalid'}, success=False)
        start('PROJ-4', '--', '--approve-for-me')
        check(last()['args'] == ['--approve-for-me'], f'{shell}: native auto review override')
        count = len(calls())
        start('PROJ-4', '--', '--permission-mode', 'auto', success=False)
        check(len(calls()) == count, f'{shell}: rejects Claude flags for Codex')
        start('PROJ-2', '--', '--sandbox', 'workspace-write', success=False)
        check(len(calls()) == count, f'{shell}: rejects Codex flags for Claude')
        start('PROJ-5', '--provider', 'unknown', success=False)
        check(not (case / 'WorkTrees/sample repo/feature-proj-5-login').exists(), f'{shell}: unsupported provider creates no worktree')
        invoke('a_c_task_start', '--provider', success=False)
        start('PROJ-6', '--provider', 'codex', '--task-text', 'implement the fixture')
        check(last()['provider'] == 'codex' and 'Read it first' in last()['args'][-1], f'{shell}: task text reaches Codex')
        check((case / 'state/descriptions/PROJ-6.md').read_text().strip() == 'implement the fixture', f'{shell}: stable task description')
        description = case / 'brief with spaces.md'
        description.write_text('file-based task')
        start('PROJ-7', '--provider', 'codex', '--task-file', '../brief with spaces.md', '-p', 'custom kickoff')
        check(last()['args'][-1] == 'custom kickoff', f'{shell}: explicit prompt wins over task file')
        check((case / 'state/descriptions/PROJ-7.md').read_text() == 'file-based task', f'{shell}: task file copied')
        start('PROJ-8', '--provider', 'codex', '--dry-run')
        check(not (case / 'WorkTrees/sample repo/feature-proj-8-login').exists(), f'{shell}: dry run creates no worktree')
        start('PROJ-4', '-c', success=False, extra={'CLI_EXIT': '23'})
        # Use an isolated PATH containing only needed utilities, with no Codex binary.
        missing = case / 'missing-bin'
        missing.mkdir()
        for utility in ('bash', 'dirname', 'pwd', 'git', 'tr', 'sed', 'basename'):
            (missing / utility).symlink_to(shutil.which(utility))
        result = start('PROJ-9', '--provider', 'codex', success=False, extra={'PATH': str(missing)})
        check('Required provider CLI not found: codex' in result.stderr, f'{shell}: missing CLI fails explicitly: {result.stderr}')
        check(not (case / 'WorkTrees/sample repo/feature-proj-9-login').exists(), f'{shell}: missing CLI creates no worktree')
        # Tab opener stub executes the generated provider launcher. Stub shell exits
        # immediately after the fake model CLI exits, so the test never opens a UI.
        write(bindir / 'zellij', '#!/usr/bin/env bash\nexit 0\n')
        write(bindir / 'test-shell', '#!/usr/bin/env bash\nexit 0\n')
        write(bindir / 'a_c_zellij_tab', '''#!/usr/bin/env bash
printf '%s\\n' "$@" > "$TAB_CAPTURE"
while [ "$#" -gt 0 ]; do
    if [ "$1" = --launcher ]; then env -u A_C_WORKFLOW_DIR -u A_TASK_WT_DIR -u MY_WORKFLOW_DIR bash "$2"; exit $?; fi
    shift
done
exit 1
''')
        tab_capture = case / 'tab-args'
        start('PROJ-10', '--provider', 'codex', '-z', 'work', '-m', 'tab-model',
              extra={'SHELL': str(bindir / 'test-shell'), 'TAB_CAPTURE': str(tab_capture)})
        check(last()['provider'] == 'codex' and last()['args'][-2:] == ['--model', 'tab-model'], f'{shell}: tab uses selected provider and model')
        check('--launcher' in tab_capture.read_text() and '--cwd' in tab_capture.read_text(), f'{shell}: delegates tabs to a_c_zellij_tab')
        start('PROJ-11', '--provider', 'claude', '-z', 'work',
              extra={'SHELL': str(bindir / 'test-shell'), 'TAB_CAPTURE': str(tab_capture), 'A_AGENT_MODE': 'agentic'})
        check(last()['provider'] == 'claude' and 'auto' in last()['args'], f'{shell}: detached launcher resolves modes without workflow env')
        print(f'PASS: {shell} task provider integration')
print(f'Passed {checks} assertions; no model/API calls')
PY
