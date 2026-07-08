---
name: a_sk_mdnest_fix
description: Quick fix workflow for mdnest — implement the fix, rebuild test instance, commit. For small bug fixes that don't need docs/website updates. Say "/a_sk_mdnest_fix" after describing the bug.
---

## Purpose

Fast-track bug fixes in mdnest: implement, build, deploy to test, verify, commit. Use this for small fixes that don't require documentation or website updates.

## Steps

1. **Implement the fix** in the appropriate file(s).

2. **Build check**:
   ```bash
   cd /Volumes/Work/Personal/repos/mdnest/frontend && npx vite build 2>&1 | tail -3
   ```
   For backend changes:
   ```bash
   cd /Volumes/Work/Personal/repos/mdnest/backend && go build -o /dev/null . && go vet ./...
   ```

3. **Deploy to test instance**:
   ```bash
   rsync -a --exclude='.git' --exclude='node_modules' --exclude='docker-compose.yml' --exclude='.env' --exclude='mdnest.conf' /Volumes/Work/Personal/repos/mdnest/ /Volumes/Work/test-ongoing-codes/mdnest-test/
   cd /Volumes/Work/test-ongoing-codes/mdnest-test && docker compose build --no-cache frontend 2>&1 | tail -2 && docker compose up -d 2>&1 | tail -3
   ```
   For backend changes, also rebuild backend:
   ```bash
   docker compose build --no-cache frontend backend
   ```

4. **Verify** — Tell the user the fix is deployed at `http://localhost:4236` and ask them to test.

5. **Commit** — Stage changed files and commit with a clear message describing the fix.

## Key Paths

- mdnest repo: `/Volumes/Work/Personal/repos/mdnest`
- Test instance: `/Volumes/Work/test-ongoing-codes/mdnest-test`
- Test URL: `http://localhost:4236`

## Commit Message Format

```
Fix: <short description>

<What was wrong and why>
<What was changed to fix it>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```
