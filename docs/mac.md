# Mac Tips

### Disk Space Analysis
```bash
du -sh -- * | sort -h
```

### Reclaim Docker Disk Space
Docker piles up stopped containers, unused images, and build cache (often tens of GB). Reclaim it safely with `a_c_docker_cleanup` (never stops running containers, never prunes volumes):
```bash
a_c_docker_cleanup --dry-run   # preview what would be removed
a_c_docker_cleanup             # safe cleanup
a_c_docker_cleanup --aggressive  # also remove unused tagged images + all build cache
```
A weekly launchd schedule ships in `launchd/com.ahsan.docker-cleanup.plist`.

### Machine gets slow after days of uptime ("red memory")

Run `a_c_mem_doctor`. Read-only by default, safe to run anywhere.

```bash
a_c_mem_doctor              # verdict + memory by app family + JVMs + candidates
a_c_mem_doctor -i           # ...then a menu of ways out. Pick one, it acts.
a_c_mem_doctor --deep       # per-process swapped-out detail (the smoking gun)
a_c_mem_doctor --reclaim    # stop idle build daemons + orphaned test forks
a_c_mem_doctor --reclaim -n # dry run of the above
a_c_mem_doctor --procs      # also show the raw per-process table
```

`-i` is the one to reach for when the machine is already unusable. It lists
each way out with the memory it frees and its risk, you pick a number, it acts,
shows the swap delta, and offers a re-scan so you can escalate one step at a
time. Apps are quit **gracefully** (Chrome keeps its tabs), never killed, and it
refuses to touch the process tree you are running it from.

**It measures with `top`, not `ps`.** This matters more than it sounds. `ps rss`
is resident-only, so on a thrashing machine it understates the worst offenders
*by design*: once a process gets compressed or swapped out its rss **shrinks**
and it looks innocent. On a live box `ps` reported WindowServer at 198MB when
its real footprint was 2756MB, and Chrome at 9.2GB when it was really 13.9GB
with 10GB compressed. Ranking by rss points you at the wrong process.

**It will not kill a running build.** A Gradle *worker* only exists while a
build is in flight, so if any worker is alive the whole Gradle family is off
limits, daemon included. `--force` overrides if you mean to abort the build.
System processes (WindowServer and friends) are shown but never offered as
restart candidates, because quitting them logs you out.

**Why a machine running JVM services dies on a multi-day curve.** A JVM commits
heap up to `-Xmx` and by default never returns it to the OS. Services that each
peaked at 4GB during a busy afternoon still hold that at midnight while idle.
macOS compresses and swaps those pages out, and then an idle JVM's periodic GC
has to walk a heap that lives on disk. That is a swap storm, and it is the
"nothing is running but the machine is dead" symptom. It compounds daily.

Memory only comes back when the owning process **exits**. There is no flush.
`sudo purge` does not help, it drops the file cache, not compressed heap.

The report groups by **app family**, not process, because a browser or Electron
app splits into dozens of helpers and no single one ever looks big enough to
blame while the family holds 9GB.

Escalation ladder, cheapest first:

1. `a_c_mem_doctor --reclaim` (build daemons, always safe, they respawn)
2. Restart the fattest JVM services one at a time
3. Quit and reopen the big families the report names
4. Quit and reopen Docker Desktop (its VM never returns memory either)
5. `a_c_restart_login` - logout/login drains everything without a reboot, and
   the machine stays up and reachable over SSH

`--reclaim` only ever stops Gradle/Kotlin/Maven daemons and test forks idle
longer than `STALE_HOURS`. It never touches your services or your IDE;
restarting those stays a manual decision.

**The durable fix** is making the JVMs hand memory back, so this stops
recurring. Per service:

```
-XX:+UseG1GC -XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=25 \
-XX:G1PeriodicGCInterval=300000
```

`G1PeriodicGCInterval` (JDK 12+) makes an idle JVM collect every 5 minutes and
uncommit the freed heap. On JDK 17+ ZGC uncommits by default
(`-XX:+ZUncommit -XX:ZUncommitDelay=300`). Also set a realistic `-Xmx` per
service, cap Docker Desktop's RAM in its settings, and in
`~/.gradle/gradle.properties`:

```
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
org.gradle.daemon.idletimeout=1800000
```


### Show Hidden Files
```bash
defaults write com.apple.Finder AppleShowAllFiles true
```

### Useful Software
- DiskCleanX - visualize directory sizes and clean up disk space
