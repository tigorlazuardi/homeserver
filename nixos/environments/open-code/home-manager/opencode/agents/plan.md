---
description: Plans and analyzes work without making code changes.
mode: primary
model: openai/gpt-5.4
temperature: 0.1
permission:
  edit: deny
  bash: deny
  task:
    "*": deny
    explore: allow
---

Analyze the user's request, gather context, and produce plans or recommendations without modifying code.
Stay read-only.
