---
name: win-safe-disk-cleanup
description: Scan Windows disk usage against a saved baseline to find what grew, and on request clean disposable caches (NVIDIA shader cache, Go build cache, VS Code VSIX downloads, Logitech G Hub and JetBrains patch downloads, old NVIDIA driver bundles) while preserving apps and personal data. Use whenever a Windows user says C: is full or low on space, asks what is eating disk space or what grew since last time, or wants to free up space or clear caches safely, even without naming the skill.
metadata:
  version: "0.1.0"
---

# Safe disk cleanup

For this user, disk scans run only when the skill is invoked. Do not create daily jobs, scheduled tasks, automations, services, or persistent watchers. A background scan means a single asynchronous scan in the current chat; wait for its result before completing the task.

Script paths below are relative to this skill's folder. Keep persistent state in `%LOCALAPPDATA%\win-safe-disk-cleanup`, the state directory. Documents is often synced by OneDrive and would upload scan results.

## Scan and compare

Run `python scripts/scan_disk.py --root C:\ --state-dir <state-directory>` in the background, because a full scan of C: can take several minutes. Keep communicating while it runs.

| Agent | How to run it in the background |
| --- | --- |
| Claude Code | Use the PowerShell or Bash tool with `run_in_background: true`. You are notified when it exits; do not poll. |
| Codex | Start it in a background execution session and check its output until it exits. |

 The script reads file metadata, skips junctions/cloud placeholders, reports inaccessible areas, and compares large files and folders with the previous completed scan. The first run establishes a baseline. File dates alone do not establish net growth.

It flags new files of at least 1 GiB, file growth of at least 1 GiB, folder growth of at least 2 GiB, a free-space fall of at least 5 GiB, or crossing below 20 GiB free. Folder sizes are logical estimates and can double-count hard links; actual free space is measured separately. Inspect the largest newly detected entities, including unknown locations; discovery does not authorize deletion.

## Clean when requested

An invocation asking to scan is read-only. When the user asks to clean, run `pwsh -NoProfile -File scripts/clean_caches.ps1 -ReportDir <state-directory>\cleanup-<yyyyMMdd-HHmmss>` first to produce a concrete plan. Inspect the category totals, skipped files, resolved roots, and running installers. Then run the same script with `-Apply` and the same `-ReportDir` within the user's authorization. Apply deletes only entries from that reviewed `cleanup-plan.json` whose roots are still current targets, so a file that aged past the cutoff after review is not removed. Some targets live under ProgramData and may need approval or elevation. Do not change permissions or retry locked files aggressively.

| Agent | When a write is blocked |
| --- | --- |
| Claude Code | Let the command's permission prompt ask the user. If Windows denies access, report those files as skipped. |
| Codex | Rerun the command with escalated permissions for targets outside the sandbox's writable roots. |

The helper only considers known NVIDIA shader caches, old VS Code extension package downloads, hashed Logitech G Hub download-cache files, Go build-cache artifacts, old JetBrains patch downloads, and obsolete NVIDIA driver-download bundles. It retains the newest NVIDIA driver bundle, files created or modified in the last 72 hours, linked paths, and locked files. It leaves directory containers in place. Never broaden its roots to entire AppData or ProgramData trees. Preserve installed extensions, plugins, applications, projects, Downloads, Documents, browser profiles, chats, databases, local history, credentials, virtual disks, restore points, Windows Installer/WinSxS, and Go module downloads. Do not uninstall apps or change shader-cache settings during routine cleanup.

If asked to remove an older GoLand version, establish actual versions from `product-info.json`, uninstall entries, `.home` pointers, and running processes. A directory named `GoLand 2025.2.3` can contain GoLand 2026.3 after in-place updates. Never remove the current installation based on its directory name. Versioned AppData folders contain settings and local history, not a second full installation. With authorization to retire an old version, preserve and verify an archive of its settings, local history, scratches, and other non-cache data before removing its obsolete profiles. Leave current-version profiles and installation untouched. If the old IDE is running, skip retiring it without terminating it.

After cleanup, report actual before/after free space, successful category totals, skipped files, and any backups. Run a fresh scan so the next invocation compares against the cleaned state. Explain that shaders/build caches will regenerate and initial games/builds may take longer. Do not promise a particular amount of free space or silently automate future deletion.

## Checks

Run `python scripts/test_scan_disk.py` after editing the scanner. For cleanup changes, run `pwsh -NoProfile -File scripts/clean_caches.ps1 -SelfTest`, review its plan, and validate that roots cannot escape through junctions or path prefixes before applying.

References: [NVIDIA shader-cache guidance](https://nvidia.custhelp.com/app/answers/detail/a_id/5735), [Go build caching](https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching), [GoLand storage and local history](https://www.jetbrains.com/help/go/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html).
