---
name: orchestrate
description: Parallel swarm orchestration using read-only scout subagents and isolated git-worktree workers. Use for multi-file features, refactors, or complex tasks that can be decomposed into concurrent implementation slices.
---

# Orchestrate Swarm Workflow

## Role of the Main Agent
- Plan, coordinate, and merge only.
- **Never edit, write, or delete source files directly.**
- Use `todo` to track progress.
- Use `scout` for read-only exploration.
- Use `worker` for isolated implementation.
- Use `bash` for git operations.

## Phase 1 — Plan & Todo
1. Understand the user goal.
2. Call `todo create` to build a task list:
   - Slice into independent, parallelizable items.
   - Use `blockedBy` only for true ordering dependencies.
   - Subject = concise imperative (e.g., "Add validation to UserService").
3. Do not spawn workers yet.

## Phase 2 — Scout
For any area lacking file/symbol context:
```json
Agent({
  "subagent_type": "scout",
  "prompt": "Find files and symbols related to <area>. Report full paths and line ranges.",
  "description": "Scout <area>",
  "run_in_background": true
})
```
- Collect results with `get_subagent_result`.
- Map findings to specific todos.

## Phase 3 — Spawn Workers
For each todo (or related group):
1. Scope the prompt to only that todo.
2. Include **only** the scout findings relevant to that scope.
3. Spawn a worker in an isolated worktree:
```json
Agent({
  "subagent_type": "worker",
  "prompt": "Task: <scoped todo>\n\nRelevant files / symbols:\n<list>\n\nExpected outcome: <brief description>\nConstraints: Only modify the listed files. Follow existing style.",
  "description": "Worker <todo>",
  "run_in_background": true,
  "thinking": "low"
})
```
4. Record the agent ID and link it to the todo ID.

## Phase 4 — Monitor
- Poll `get_subagent_result` for each worker.
- Steer with `steer_subagent` if a worker diverges.
- On completion, note the branch name: `pi-agent-<id>`.

## Phase 5 — Merge
1. Ensure the working tree is clean (`git status`). Ask user to stash if dirty.
2. For each worker branch:
```bash
git merge --no-ff pi-agent-<id> -m "Merge worker <id>: <description>"
```
3. If conflicts appear:
   - Read conflicted files.
   - Resolve trivial ones; stop and ask the user for complex conflicts.
   - `git add` and `git commit` to finish.
4. Update the matching todo to `completed`.

## Phase 6 — Finalize
- Summarize merged branches, changed files, and caveats.
- Optionally clean up branches:
```bash
git branch -d pi-agent-<id>
```
- After merging, review manually or run `/skill:review` to audit changes against project standards.

## Key Constraints
- Workers get **scoped todos + scoped file lists**, never the full plan.
- Scout is **read-only**; never ask it to edit.
- Workers run in **worktrees** for isolation.
