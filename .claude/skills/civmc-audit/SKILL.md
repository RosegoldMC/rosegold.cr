---
name: civmc-audit
description: Audit rosegold.cr against CivMC server rules
argument-hint: [full]
---

# CivMC Compliance Audit

Audit the rosegold.cr codebase against CivMC server rules for bot compliance.

## Determine Audit Mode

1. Check if `$ARGUMENTS` contains "full". If so, use **full codebase mode**.
2. Otherwise, check the current git branch:
   - Run `git rev-parse --abbrev-ref HEAD` to get the branch name
   - If on `main`, or if `git diff main...HEAD --name-only` produces no output, use **full codebase mode**
   - Otherwise, use **branch diff mode**

## Dispatch the Auditor

Use the Agent tool with `subagent_type: "civmc-auditor"` to dispatch the audit agent.

Pass a prompt containing:
- The audit mode (branch diff or full codebase)
- The branch name
- Today's date
- If branch diff mode: the list of changed `src/rosegold/` files from `git diff main...HEAD --name-only`
- Reminder: this is research only — do NOT edit any files

## Present Results

After the agent completes, present the full audit report to the user. Do not summarize — show the complete checklist output.
