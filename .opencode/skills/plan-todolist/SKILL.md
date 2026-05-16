---
name: plan-todolist
description: Research a complex task and produce a round-by-round execution plan with a progress checklist that a high-level orchestrator can use to dispatch work to subagents and track completion. Use when planning a multi-round feature, refactor, migration, or other complex cross-file task.
---

# Plan Todolist

Produce a structured, round-by-round execution plan for a complex task so that a high-level orchestrator agent can dispatch each round to subagents in isolated contexts, track progress by updating the plan file, and push the work forward incrementally.

## When to Use

- A task is too large or cross-cutting for a single agent pass.
- You need to break work into sequential or partially parallel rounds with clear handoff points.
- You want a persistent plan file that an orchestrator can update round by round to track completion.
- You need subagents to work in isolated contexts with explicit input and output contracts per round.

## Output

A single Markdown file at the workspace root unless the user asks for a different location.

The file contains these sections in order:

1. **Design Summary**: What, why, recommended approach, key decisions, and scope boundaries.
2. **Relevant Files**: Full paths with brief descriptions of what to modify or reuse.
3. **Execution Rounds**: Numbered rounds, each with goal, subtasks, expected output, and acceptance criteria.
4. **Orchestrator Notes**: Dependency graph, parallelism opportunities, and mandatory sequencing.
5. **Progress Checklist**: A flat `- [ ]` checklist covering every round and subtask.
6. **Progress Update Template**: A copy-paste template the orchestrator fills in after each round completes.
7. **Subagent Prompt Skeleton**: The minimum context every subagent dispatch must carry.

## Constraints

- Do not start implementation. This skill only produces the plan file.
- Do not guess at codebase structure. Use read-only exploration to gather real context before writing rounds.
- Do not leave ambiguous round boundaries. Each round must have a concrete acceptance criterion that can be verified without reading the next round.
- Do not create rounds that are too large to fit in a single subagent context window. Split further if needed.
- Do not omit the progress checklist. It is the primary tracking surface for the orchestrator.
- The plan file must be self-contained: a future agent reading only this file should understand the full task, decisions, and execution flow.

## Procedure

### Phase 1: Discovery

1. Read the user's task carefully and identify the what, why, and scope boundaries.
2. Launch read-only exploration subagents to gather codebase context. When the task spans multiple independent areas, launch 2 to 3 subagents in parallel.
3. Check any repository knowledge files that may inform the plan.
4. Identify analogous existing implementations that can serve as reference patterns.

### Phase 2: Alignment

5. If research reveals major ambiguities, use `AskQuestion` to clarify them with the user.
6. If answers significantly change scope, loop back to discovery.
7. Record key decisions, confirmed scope, rejected alternatives, and chosen patterns in the design summary.

### Phase 3: Round Design

8. Group the work into rounds. Each round should be independently verifiable, bounded enough for one subagent pass, and explicit about dependencies.
9. For each round, write:
   - **Goal**: one sentence.
   - **Subtasks**: lettered items with concrete actions.
   - **Expected output**: files changed, APIs added, or behaviors verified.
   - **Acceptance criteria**: how to know the round is done.
10. Write the orchestrator notes section covering dependencies, parallelism, mandatory sequencing, and global invariants.

### Phase 4: Checklist and Templates

11. Generate the progress checklist with one `- [ ]` line per round and per subtask.
12. Generate the progress update template with a fill-in-the-blank status block.
13. Generate the subagent prompt skeleton with the minimum required context payload for every round dispatch.

### Phase 5: Output

14. Write the complete plan file to the target location.
15. Show a scannable summary of the plan to the user.
16. Ask the user for approval or revision if the task has meaningful open questions.

## Round Design Guidelines

- Prefer 3 to 6 rounds for most tasks.
- Round 0 should be a read-only baseline or discovery round when the design is still ambiguous.
- The final round should include regression verification and knowledge capture.
- If two subtasks within one round have no dependency on each other, mark them as parallelizable.
- Each round's acceptance criteria should be testable: build command, runtime check, log inspection, or specific file state.

## Progress Update Template Shape

```markdown
### Round N Status
- Status: Not started / In progress / Complete / Blocked
- Completed:
  - Subtask A description
  - Subtask B description
- Files changed:
  - path/to/file
- Verified:
  - Acceptance criterion 1
  - Acceptance criterion 2
- Risks & blockers:
  - Risk A
- Next-round input context:
  - Conclusion A
  - Constraint B
```

## Subagent Prompt Skeleton Shape

Every round dispatch to a subagent must include at minimum:

- Current round number and goal
- Acceptance criteria for this round
- Global constraints that apply to all rounds
- Files allowed to be modified in this round
- Required report-back: files changed, verification results, remaining risks, and next-round recommendations
