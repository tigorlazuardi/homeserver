---
name: review
description: Review code changes via git diff against project standards (AGENTS.md / CLAUDE.md). Spawns a read-only reviewer subagent with fresh context. Use after merges or before commits to audit compliance.
---

# Review Workflow

## 1. Capture Diff
Determine the diff range:
- If user provided a range (e.g. `HEAD~2..HEAD`, `<branch>..HEAD`), use it.
- Otherwise default to unstaged + staged changes:
```bash
git diff HEAD
```

Save the diff to a temporary file if it is large:
```bash
git diff <range> > /tmp/review-diff.patch
```

List changed files:
```bash
git diff --name-only <range>
```

## 2. Load Project Rules
Read project standards if they exist:
- `AGENTS.md`
- `CLAUDE.md`
- `.pi/AGENTS.md`
- Any `.md` files in `.pi/agents/rules/`

If none found, note: "No project standards found; reviewing for general best practices only."

## 3. Spawn Reviewer
Spawn the `reviewer` subagent with **fresh context** and pass the diff + rules:

```json
Agent({
  "subagent_type": "reviewer",
  "prompt": "Review the following code changes.\n\n## Changed files\n<list of changed files>\n\n## Git diff\n```diff\n<git diff content>\n```\n\n## Project standards\n<AGENTS.md / CLAUDE.md content or 'None found'>\n\nCheck:\n- Naming conventions\n- Architecture / design patterns\n- Error handling\n- Testing coverage\n- Security / performance\n\nReport findings grouped by severity:\n- **Blocker** — must fix\n- **Warning** — should fix\n- **Nit** — minor suggestion\n\nInclude file paths and line ranges for each finding.",
  "description": "Review code changes",
  "run_in_background": true,
  "thinking": "low"
})
```

## 4. Collect Result
Wait for completion:
```json
get_subagent_result({ "agent_id": "<reviewer-id>", "wait": true })
```

## 5. Present Findings
- Summarize blocker / warning / nit counts.
- If blockers exist, recommend spawning `worker` subagents to fix them.
- If no issues, confirm compliance.
