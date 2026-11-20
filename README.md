# AI skills

| Skill | What it does |
| --- | --- |
| [backlog](backlog/SKILL.md) | Keeps a Git repo's deferred work in `docs/backlog/`, one file per item. Lists, verifies, and works items one at a time, and files new ones without polluting feature branches. |
| [review-loop](review-loop/SKILL.md) | Runs an independent code review. Codex asks Claude Code to review and vice versa. If the other CLI is unavailable, the host uses its own review subagent. |
| [win-safe-disk-cleanup](win-safe-disk-cleanup/SKILL.md) | Compares Windows disk usage with a previous scan and cleans disposable caches and old installer downloads when requested. |
| [winget-updates](winget-updates/SKILL.md) | Reviews or installs major and minor Windows package updates through WinGet. |

## Install

Clone this repository or open your existing copy in Codex or Claude Code. Give each agent you want to use this prompt.

> Install all four skills from this repository as personal skills for this agent. Copy each complete skill folder, including its scripts and supporting files, and verify that each installed folder contains its SKILL.md.
