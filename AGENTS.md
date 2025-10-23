
Agent Workflow (Issue → Branch → Draft PR → Logs → CI → Review → Merge)

Principles: keep it cing2 cing4 (clear), hou2 (good), and mai5 (don’t) leak secrets.

Every change starts as a GitHub Issue (use the template).

Create one feature branch per Issue: feat/<slug>, fix/<slug>, chore/<slug>.

Make tiny commits using Conventional Commits.

Open a Draft PR early; title/body reference the Issue (e.g., Fixes #123).

Let CI run (lint, tests, coverage ≥85%); no red merges.

Use Issue comments as a progress log (one per major step).

Review → squash merge → close Issue → append to logs/DEVLOG.md.

Codex CLI usage

Keep prompts short (faai3): “Read AGENTS.md, implement X in small commits, open Draft PR linked to #N, log progress.”

Prefer codex (interactive) or codex exec "<instruction>" for single-shot tasks.
