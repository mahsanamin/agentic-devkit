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

### Show Hidden Files
```bash
defaults write com.apple.Finder AppleShowAllFiles true
```

### Useful Software
- DiskCleanX - visualize directory sizes and clean up disk space
