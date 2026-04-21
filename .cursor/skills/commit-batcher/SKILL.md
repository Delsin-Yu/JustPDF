---
name: commit-batcher
description: Review a large git worktree, group changes into small coherent batches, create clear English commit messages, and explain the per-batch rationale in reusable commit-detail bullets. Use when the user asks to split commits, batch commits, review workspace changes, or restructure commit history without rewriting existing commits.
---

# Commit Batcher

## When to Use

- Split a broad refactor into small reviewable commits.
- Review current workspace changes before staging.
- Create clear English commit messages for coherent batches, including reusable detail bullets in the commit body.
- Produce clear per-batch rationale that can be reused as commit description or review notes.
- Leave ambiguous or local-only files out of functional commits.

## Constraints

- Do not create one large catch-all commit unless the user explicitly asks for it.
- Do not mix unrelated local or temporary files into product-code commits.
- Do not rewrite history, amend commits, or discard user changes unless the user explicitly asks.
- Do not rely on assumptions about grouping until you inspect the actual git diff.
- Only commit batches that are understandable on their own.
- Do not stop at naming the batch; explain why the files belong together and what technical intent the batch represents.
- Do not return vague rationale such as "related changes" or "same feature"; tie the grouping back to concrete API, model, workflow, or behavior changes.
- Never put commit-splitting rationale, batching justification, or exclusion notes into the actual git commit message body.
- Treat grouping rationale as chat output only unless the user explicitly asks to preserve that rationale outside the commit object.

## Procedure

1. Inspect git status, changed files, and diff summaries to understand the scope.
2. If the change set is large, use the `sub-runner` subagent for read-only analysis to propose safe commit groupings before staging anything.
3. Identify local-only, generated, temporary, debug, or editor-specific files that should be excluded or isolated.
4. For each proposed batch, write down the grouping basis before staging: the shared technical intent, why the files belong together, and what key changes define the batch.
5. Stage one coherent batch at a time, sanity-check the staged diff, prepare 2 to 5 reusable English detail bullets that describe only the staged changes, then commit using a multi-line message whose first line is a concise English title, followed by exactly one blank line, and then the detail bullets.
6. Treat the `提交细节` bullets as part of the actual commit message body by default, not merely as notes returned in chat, unless the user explicitly asks for title-only commits.
7. Before committing, verify that the detail bullets still match the staged diff rather than the earlier proposed grouping, and correct them if staging changed the scope.
8. Repeat until all commit-worthy batches are handled, and leave questionable leftovers uncommitted with a short explanation.
9. When practical, run a build or the most relevant verification step after major batches to reduce the risk of broken history.

## Commit Rules

- Prefer small commits that map to one intent, such as a model refactor, UI adaptation, resource migration, or cleanup.
- Commit messages must be in English and easy to understand.
- The default commit message format is: first line as a short verb-phrase title, then exactly one blank line, then 2 to 5 `- ` bullet lines as the commit body.
- Do not place the first detail bullet on the line immediately after the title; the blank line between subject and body is mandatory.
- When using git commands that accept a single message string, ensure the string contains `title + "\n\n" + body` rather than `title + "\n" + body`.
- If a file is local configuration, debug scaffolding, or otherwise ambiguous, keep it out of functional commits unless its purpose is verified.
- For every batch, include a concrete `分组依据` explanation tied to APIs, type signatures, runtime flow, data model changes, or documentation scope.
- For every batch, prepare reusable `提交细节` bullets that are written into the commit message body and can also serve as review notes or changelog fragments.
- Commit-message bullets must describe concrete staged changes only; they must not talk about why files were split, why other files were excluded, or why neighboring batches were kept separate.
- Avoid generic detail bullets such as "优化代码结构" or "更新相关内容" unless they are backed by specific technical points.

Example commit message shape:

```text
Support manual assembly types to skip auto-assembly diagnostics

- Add ManualAssemblyAttribute to mark types that are manually assembled by the developer.
- Add unified attribute recognition logic in the generator to match class name, English name, and fully qualified name.
- Skip manually assembled concrete classes during interface implementation scanning to avoid false diagnostics.
```

## Verification Guidance

- Prefer the repository's existing build or test tasks over ad-hoc wrappers.
- When validating commit message formatting, inspect a raw or medium-detail git log view rather than `--oneline`, and confirm there is a blank line between the subject and the first detail bullet.
- If a batch changes runtime behavior, run the most relevant targeted verification you can before moving to the next batch.

## Output Format

Return:

1. A brief summary of the grouping strategy.
2. For each proposed or created batch: file list, grouping rationale, and 2 to 5 commit-detail bullets written in English.
3. The commits created, in order, with their commit hashes and full English commit messages, including the detail-bullet body.
4. Any files intentionally left uncommitted, with the reason.
5. The verification you ran, or a short note if verification was not possible.
