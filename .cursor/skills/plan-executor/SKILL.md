---
name: plan-executor
description: Act as a high-level orchestrator that reads a plan-todolist file, dispatches each round to subagents, updates progress in the plan file, and keeps going until every item is completed. Use when the user wants a multi-round plan executed rather than implemented directly in one pass.
---

# Plan Executor

Act as a high-level workspace orchestrator. Read a `plan-todolist` file, then drive it to completion by dispatching each round to subagents and updating the plan file after every round.

## When to Use

- A `plan-todolist` file already exists and you want to execute it round by round.
- You need an orchestrator that delegates work instead of doing it directly.
- You want automatic progress tracking inside the plan file itself.

## Core Rules

1. **You are an orchestrator, not an implementer.** Do not write production code yourself. Route implementation work through subagents.
2. **Do not stop until the todolist is fully completed** or you hit an unrecoverable blocker that requires user input.
3. **Update the plan file after every round.** Check off completed items, fill in the progress update block, and record risks or blockers.
4. **Respect round dependencies.** Do not start a round whose prerequisites are incomplete. If two rounds or subtasks are independent, dispatch them in parallel.
5. **Carry explicit context to every subagent.** Inline the constraints and acceptance criteria rather than referencing the plan file abstractly.

## Procedure

### Startup

1. Read the plan file. If the user did not specify a path, look for `plan-todolist.md` at the workspace root, then fall back to similar root-level plan files.
2. Parse current progress and identify which rounds are complete, in progress, or not started.
3. Identify the next actionable round whose dependencies are complete.

### Round Dispatch Loop

4. Prepare the subagent prompt for the current round. It must include:
   - The round number and goal
   - All subtasks for the round
   - The acceptance criteria
   - The inlined global constraints
   - The list of files in scope
   - The required report-back format
   - Any input context carried forward from previous rounds
5. Dispatch the round via `Subagent`.
   - Use `sub-runner` for complex, multi-file, or reasoning-heavy rounds.
   - Use the built-in `explore` subagent for read-only discovery or baseline rounds.
   - Use a straightforward implementation subagent when the round is narrow and simple.
   - When a round contains independent subtasks, dispatch them in parallel.
6. Process the result.
   - Read the subagent report: files changed, verification results, risks.
   - If the subagent reports a blocker, decide whether to retry, adjust, or ask the user for guidance.
   - If the subagent succeeded, update the plan file.
7. Update the plan file in place.
   - Check off completed subtask items in the progress checklist.
   - If all subtasks for the round are done, check off the round-level item.
   - Fill in or append a progress update block for the round.
   - Record any risks or next-round context reported by the subagent.
8. Advance to the next round and repeat until every round-level checkbox is checked.

### Completion

9. When all rounds are complete:
   - Review the plan file to ensure all checkboxes are checked.
   - Summarize the outcome to the user, including what was done, what was verified, and any residual risks.
   - If the plan calls for knowledge capture, complete it or remind the user.

## Error Handling

- **Subagent partial failure**: Check off completed subtasks, record the failure in the round status block, and redispatch only the remaining work.
- **Build or verification failure**: Record the failure details. If the fix is obvious and bounded, dispatch a follow-up subagent for that specific fix. Otherwise, escalate to the user.
- **Repeated failure on the same round**: After two failed attempts, stop and ask the user for guidance rather than brute-forcing.

## Subagent Prompt Template

Use this as the base for every dispatch. Fill in the bracketed fields from the plan file.

```text
You are executing Round [N] of a multi-round implementation plan.

## Goal
[Round goal from plan]

## Subtasks
[Lettered subtask list from plan]

## Acceptance Criteria
[Acceptance criteria from plan]

## Global Constraints
[Inlined global constraints or orchestrator notes from plan]

## Files in Scope
[List of files this round may read or modify]

## Input Context from Previous Rounds
[Carried-forward conclusions, constraints, or API surfaces from prior rounds]

## Required Report
When done, return:
1. Files changed
2. Verification results
3. Remaining risks or open questions
4. Recommendations for the next round
```

## Plan File Format Expectations

The orchestrator expects the plan file to contain at minimum:

- A `## Progress Checklist` section with `- [ ]` items
- A `## Execution Rounds` or `### Round N` structure
- A `## Subagent Prompt Skeleton` or global constraints section
- A `## Progress Update Template` section

If any section is missing, warn the user and continue with the best workable interpretation.
