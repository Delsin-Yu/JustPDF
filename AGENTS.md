
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
- **Runtime debug logs go through `hilog`, not localhost ingest.** The app runs on the HarmonyOS device. `fetch` / HTTP to `127.0.0.1` from the device does not reach the PC, so Cursor debug-ingest URLs will stay empty. Instrument with `hilog` (`import { hilog } from '@kit.PerformanceAnalysisKit'`), use a distinctive tag (for example `hilog.info(0, 'DBG-justpdf', 'location|message|data')`), deploy, then collect with `devecocli log --device <id> --bundle-name deyu.just.pdf --follow` and search that capture for the tag. Remove the temporary logs after the issue is confirmed.

## HarmonyOS documentation

- For HarmonyOS related questions, ALWAYS search the local HarmonyOS developer docs before relying on general knowledge.
- Docs live at the **sibling** path `d:\Repos\HarmonyOS-Developer-Docs\` (not under this repo root). Use `devecocli docs search/read` or read those files directly.
- The local copy matches the online documentation; performing web search over the online version is strictly prohibited.
- Useful local roots (under `d:\Repos\HarmonyOS-Developer-Docs\`):
  - Guides: `guides/`
  - API references: `references/`
  - Best practices: `best-practices/`
  - FAQs: `faqs/`
  - Release notes: `releases/`
- Each `.md` file contains YAML frontmatter with `source_url` pointing to the original online page.
- Every directory has an `index.md` listing its contents for navigation.

## Architecture notes

Single Entry HAP + one UIAbility. Logical layers (product → features → common); common never depends upward. Stay on one HAP — do not introduce Feature HAP/HAR unless a later program explicitly requires it.

### Ownership map

| Layer | Path | Owns |
|-------|------|------|
| product | `entry/src/main/ets/product/entryability/`, `product/entrybackupability/`, `product/pages/Index.ets` | Ability lifecycle, landing/picker |
| features/viewer | `features/viewer/PDFView.ets` + page-turn/link/session/slot/VM/chrome pieces | Viewer shell, page-turn, links, slots |
| features/annotation | `features/annotation/PDFAnnotation*` | Draw/erase/save/import |
| features/panels | `features/panels/` (bookmark + FloatingPanel*) | Dock/float overlays |
| features/music | `features/music/` metronome/tuner | Audio tools hosted by viewer |
| features/continuation | `features/continuation/` | Cross-device migrate/restore |
| common/document | `common/document/` (`DocumentOpenService`, `PdfDocumentLoader`) | URI→sandbox, PDF load helpers |
| common/page | `common/page/` (`PageStore`, `PageInfo`, strokes, raster, links) | Page model + cache |
| common/session | `common/session/AppSession` | Typed AppStorage key access |
| common/ui | `common/ui/` (dialogs, Numbers, RecentFiles, etc.) | Shared UI helpers |
| navigation | `navigation/PendingDocumentOpen.ets` | Unsaved-guarded document replace |

Router page URLs (must match `main_pages.json`): `product/pages/Index`, `features/viewer/PDFView`.

### Entry points and navigation

- `entry/src/main/ets/product/entryability/EntryAbility.ets`: app lifecycle, window management, handles PDF file URIs from system intents.
- `entry/src/main/ets/product/pages/Index.ets`: file picker landing page; routes to PDFView with sandbox file path.
- `entry/src/main/ets/features/viewer/PDFView.ets`: main PDF viewer shell; composes controllers and UI.

### Data flow

1. Files are copied from system URI to sandbox (`tempDir`) before loading via `DocumentOpenService`.
2. `PageStore` manages pages with lazy thumbnail/cache loading (`IDataSource`).
3. Page rendering uses `@kit.PDFKit` `pdfService` with multi-scale PixelMap caching (custom path, not system `PdfView`).
4. Strokes are stored per-page in `PageInfo.strokes[]` and rendered via Canvas overlay.

### Memory management

- Call `evictAllViewerCaches()` / thumbnail release when pages scroll out of view.
- Use `prefetchPagesAround(centerIndex, prefetchRange, evictionRange, displayedPageIndices)` for smart caching.
- Honor `onMemoryLevel` → `PageStore.applyMemoryPressure`.

## Agent-friendly coding rules

1. **Ownership**: change files inside the owning folder; PDFView should only compose controllers and `build()`.
2. **File budget**: prefer &lt; ~800 lines for page shells; &lt; ~1200 for controllers; split when exceeded.
3. **No new AppStorage string keys** outside `common/session/AppSession` (or the session module once present).
4. **Controllers take narrow interfaces** (`StrokeStore`, `DocumentIO`, `PageNavigator`) — not large closure bags over `@Local`.
5. **Inline** one-line / single-caller thin wrappers; keep real FSMs as named classes.
6. **Side effects stay in one place per concern** (e.g. page-turn commit only in the page-turn controller).
7. **Verify** with `.\build.ps1` after structural changes; for API questions use `devecocli docs search/read` or local docs.
8. Naming: use `PageStore` (not `PageInfoDataSource`).

## Manual regression checklist

Smoke these after each refactor round:

1. Open PDF from Index picker and from recent list.
2. Open PDF via system Want / share into the app (cold and warm while viewer active).
3. Password-protected PDF: correct password loads; cancel leaves cleanly.
4. Horizontal slide page-turn (commit + cancel) in 1/2/3-column modes.
5. Pan/zoom; stylus annotate draw/erase; undo/redo; save; leave with unsaved prompt.
6. Bookmark panel + floating metronome/tuner/annotation palette dock/float/scale.
7. Cross-device continuation migrate/restore (if hardware available).
8. Memory pressure path does not crash (scroll far + background).
9. Share / export from viewer still works.
