# Contributing

Skills in this repository are tested in Claude Code and Codex. Each skill must work in both.

## Agent-specific instructions

- Write agent-neutral instructions where you can. Describe the goal and the exact command, not one agent's tool names, UI, or sandbox terms. For example, write "run the scan in the background and keep responding" rather than "use a background execution session".
- When behavior has to differ, give exact instructions for each agent side by side. A table with a Claude Code row and a Codex row works well. See "Choose the reviewer" in [review-loop](review-loop/SKILL.md).
- Don't add instructions for other agents. Only Claude Code and Codex are tested, so other agents follow the neutral instructions.
