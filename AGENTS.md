
# JustPDF Project Guidance

Shared agent harness (Cursor, GitHub Copilot, OpenCode): edit **`AGENTS.md`** for workspace rules and **`.agents/skills/<name>/SKILL.md`** for skills. Do not duplicate rules or skills under `.cursor/`, `.github/`, or `.opencode/`.

Treat this rule as workspace-wide policy. When it conflicts with default agent habits, follow this rule. Prefer explicit repository-safe behavior over implicit editor defaults.

## Default behavior

- When summarizing the final result of a task, ALWAYS begin your response by telling me what AI model you are using in the format of: "This is `[model name]` speaking,\n". The model name should be followed by single like: `claude-3.5-sonnet`, `gemini-2.5-pro`, etc, it is strictly forbidden to not tell me the model name, or infer the model name from the previous conversation context.

## Project overview

- This project is a HarmonyOS PDF reader built with ArkTS and ArkUI for phones, tablets, and 2-in-1 devices.
- Treat ArkTS like strict TypeScript: keep types explicit, avoid untyped patterns, and prefer clear async/await flows.
- Keep UI text and code comments in Simplified Chinese. Keep variable, function, type, and file-level identifiers in English.
- Use `hilog` for logging (for example `hilog.info(0, 'PDFView', 'message')`).
- Wrap async operations in try-catch, and show `AlertDialog` for user-facing errors.

## Builds and diagnostics

- To actually check for syntactical correctness and build errors, always use `.\build.ps1` to build the project.
- Initial syntax diagnostics from OpenHarmony tooling may be false positives; prefer HarmonyOS and DevEco Studio behavior when they disagree.

## HarmonyOS documentation

- For HarmonyOS related questions, ALWAYS search the local `HarmonyOS-Developer-Docs/` guides and references before relying on general knowledge.
- The local `HarmonyOS-Developer-Docs/` is a copy of the online documentation, so it is up to date and complete; performing web search over the online version is strictly prohibited, and is considered a violation of the rules.
- Useful local roots:
  - Guides: `HarmonyOS-Developer-Docs/guides/`
  - API references: `HarmonyOS-Developer-Docs/references/`
  - Best practices: `HarmonyOS-Developer-Docs/best-practices/`
  - FAQs: `HarmonyOS-Developer-Docs/faqs/`
  - Release notes: `HarmonyOS-Developer-Docs/releases/`
- Each `.md` file contains YAML frontmatter with `source_url` pointing to the original online page.
- Every directory has an `index.md` listing its contents for navigation.

## Architecture notes

### Entry points and navigation

- `entry/src/main/ets/entryability/EntryAbility.ets`: app lifecycle, window management, handles PDF file URIs from system intents.
- `entry/src/main/ets/pages/Index.ets`: file picker landing page; routes to PDFView with sandbox file path.
- `entry/src/main/ets/pages/PDFView.ets`: main PDF viewer; rendering, gestures, annotations.

### Data flow

1. Files are copied from system URI to sandbox (`tempDir`) before loading.
2. `PageInfoDataSource` manages `PageGroup[]` containing `PageInfo[]` with lazy thumbnail/cache loading.
3. Page rendering uses `@kit.PDFKit` with multi-scale caching.
4. Strokes are stored per-page in `PageInfo.strokes[]` and rendered via Canvas overlay.

### Memory management

- Call `evictViewerCache()` / `evictThumbnail()` when pages scroll out of view.
- Use `prefetchPagesAround(centerIndex, prefetchRange, evictionRange)` for smart caching.
