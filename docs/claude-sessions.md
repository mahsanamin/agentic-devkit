# Claude sessions dashboard (`a_c_claude_sessions`)

A live dashboard of the Claude Code sessions running on this machine: one row per
running `claude` CLI process with its exact session id, ai title, project/branch,
and the last thing it was asked to do, newest activity on top. It can also search
every session on disk (live or closed) to recover one you closed.

The whole thing is one script: `scripts/a_c_claude_sessions`. It is on PATH once
the my_setup shell profile is sourced, so you run it by name from anywhere.

## Run it once (no setup, nothing persistent)

```bash
a_c_claude_sessions                 # Markdown snapshot of live sessions to stdout
a_c_claude_sessions --json          # same, as JSON
a_c_claude_sessions --serve         # live web page at http://127.0.0.1:8787 (this machine only)
a_c_claude_sessions --serve --tailscale   # live web page on this host's tailnet IP
a_c_claude_sessions --write-mdnest  # write the Markdown dashboard to the mdnest note
a_c_claude_sessions --find "docker cleanup"   # find a session (live or closed) + resume command
```

- `--serve` binds `127.0.0.1` (only this machine) by default.
- `--tailscale` binds this host's own Tailscale IP, so any device on your tailnet can
  reach it, but the LAN and public internet cannot. The IP is auto-detected, so this
  is not tied to one machine.
- `--bind ADDR` binds any address you choose (e.g. `0.0.0.0` for every interface).

## Make it always-on (survives reboots)

The launchd agents are **generated from this machine's own paths at install time**,
so the same command works on any Mac that has the my_setup repo set up. Nothing is
hardcoded to one machine (that is why there are no static plist files in the repo).

```bash
a_c_claude_sessions --install-web-agent        # serve on the tailnet at boot (port 8787)
a_c_claude_sessions --install-web-agent 9000   # ... on a different port
a_c_claude_sessions --install-mdnest-agent     # refresh the mdnest note every 10 min
```

Remove them:

```bash
a_c_claude_sessions --uninstall-web-agent
a_c_claude_sessions --uninstall-mdnest-agent
```

Each install writes a plist into `~/Library/LaunchAgents/`, loads it, and prints the
plist path, the log path, and the URL it is serving. The web agent uses `KeepAlive`,
so if Tailscale is not up yet at login it keeps retrying until the tailnet address
exists.

## Taking it to another machine

1. Get the my_setup repo on that machine and run `./install.sh` (see the repo
   README). That puts `scripts/` on PATH.
2. `source ~/.zshrc` so `a_c_claude_sessions` resolves.
3. For a one-off view: `a_c_claude_sessions --serve --tailscale`.
4. To keep it running: `a_c_claude_sessions --install-web-agent`.

That machine will serve on its **own** Tailscale IP (auto-detected), not this one's.
Find that machine's IP with `tailscale ip -4`.

## Logs and manual control

- Web log: `~/Library/Logs/a_c_claude_sessions_web.launchd.log`
- mdnest log: `~/Library/Logs/a_c_claude_sessions.launchd.log`
- Registered agents: `launchctl list | grep claude-sessions`
- Restart after a code change: `launchctl kickstart -k gui/$(id -u)/com.ahsan.claude-sessions-web`

## Accuracy note

Session id is exact for remote-control, forked, and resumed sessions (their id is in
the command line). For a plain interactive session the id is inferred as the most
recently active session in that working directory, so two plain sessions in the same
folder can collapse into one row.

## What is visible on the network

The dashboard shows the prompt text of each session (the "doing" column). When served
with `--tailscale`, anyone on your tailnet who opens the URL can read it. That is your
own devices, but keep it in mind.
