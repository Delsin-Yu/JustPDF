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

## Builds, products, and signing

`signingConfig` is on the **product**, not on `buildMode`. In `build-profile.json5`: product `default` → signingConfig `debug`; product `release` → signingConfig `release`. Scripts map `-BuildMode release` to product `release`, otherwise `default` (`Resolve-JustPdfProductName` in `deveco-cli.ps1`). Signed HAP: `entry/build/<product>/outputs/default/entry-default-signed.hap` or `entry-<product>-signed.hap`.

Never commit `certs/` (gitignored). Installing debug over release (or the reverse) on the same device fails with `install provision type not same` (9568286) — uninstall first, then install.

Root entry scripts (use these; do not invent parallel wrappers):

- `.\check.ps1` — ArkTS lint (`devecocli check lint`). `--incremental` for uncommitted files. This is the HarmonyOS checker — not generic TypeScript / OpenHarmony squiggles.
- `.\build.ps1` — HAP compile/sign.
- `.\build-deploy-run.ps1` — build, install, launch on connected devices.
- `.\build-deploy-debug.ps1` — same, then `aa start -D` (may wait at splash until a debugger attaches).
- `.\deploy.ps1` — install an existing HAP and launch (no build).
- `.\apply.ps1` — after a successful full deploy, iterate with `devecocli run --apply`.
- `.\lsp.ps1` — `devecocli serve lsp --arkts` for stdio clients.
- `.\crash-log.ps1` — `devecocli log --crash`.
- `.\ui-inspect.ps1` — on-device screenshot / layout.
- `.\connect-wifi.ps1` — interactive HDC WiFi connect.

Shared helpers (not user entrypoints): `hdc-target.ps1`, `deveco-cli.ps1`.

`.cursor/mcp.json` is the full DevEco MCP (`devecocli serve mcp`). Fast check can use MCP `check` or `.\check.ps1`. Editor LSP: HarmonyOS-ArkTS (`huawei-developer.arkts-language-client`) with `arkts.deveco.path`. Command: `ArkTS: Restart Language Server`.

## Devices and HDC

USB once to enable TCP debugging (`tmode port`); afterward `.\connect-wifi.ps1` (`tconn IP:port`). Device ports are high; host listen is 8710. Bundle `deyu.just.pdf`, ability `EntryAbility`.

`hdc discover` LAN UDP often returns `total:0` — expected. Do not spray the gitignored `.connect-wifi-history.txt` as a reconnect strategy.

## Diagnostics

- **Runtime logs go through `hilog`, not localhost ingest.** The app runs on the device. `fetch` / HTTP to `127.0.0.1` from the device does not reach the PC. Instrument with `hilog` (`import { hilog } from '@kit.PerformanceAnalysisKit'`), a distinctive tag (for example `hilog.info(0, 'DBG-justpdf', 'location|message|data')`), deploy, then `devecocli log --device <id> --bundle-name deyu.just.pdf --follow` (or `.\crash-log.ps1`). Remove temporary logs after the issue is confirmed.
- **On-device UI**: `.\ui-inspect.ps1 -Action screenshot` / `-Action layout`, or `devecocli ui click|swipe|text`. Layout dump is the visible tree only — scroll the target on-screen first.

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

Single Entry HAP + one UIAbility. Logical layers (product → features → common); common never depends upward. Stay on one HAP — do not introduce Feature HAP/HAR unless a later program explicitly requires it. `entry/src/ohosTest` is an in-entry test module, not a Feature HAP.

`entry/src/test` and `entry/src/ohosTest` are scaffolds only — do not treat them as regression coverage.

### Ownership map

| Layer | Path | Owns |
|-------|------|------|
| product | `product/entryability/`, `product/entrybackupability/`, `product/pages/Index.ets` | Ability lifecycle, landing/picker |
| features/viewer | `features/viewer/` | Viewer shell, page-turn, links, slots, chrome, action menu, jump history |
| features/annotation | `features/annotation/` | Draw/erase/save/import, palette, custom color, layer panel |
| features/panels | `features/panels/` | Bookmark + dock/float overlays |
| features/music | `features/music/` | Metronome/tuner hosted by viewer |
| features/continuation | `features/continuation/` | Cross-device migrate/restore/session/distributed/permission |
| common/document | `common/document/` | URI→sandbox, PDF load helpers |
| common/page | `common/page/` | PageStore, raster, render session, worker protocol, memory pressure, annotation layer |
| workers | `workers/PdfRenderWorker.ets` | Off-main-thread PDF raster |
| common/session | `common/session/AppSession` | Typed AppStorage key access |
| common/ui | `common/ui/` | Dialogs, Numbers, RecentFiles, Settings, Tutorial, insets |
| navigation | `navigation/PendingDocumentOpen.ets` | Unsaved-guarded document replace |

Paths above are under `entry/src/main/ets/`. Router page URLs (must match `main_pages.json`): `product/pages/Index`, `features/viewer/PDFView`.

### Entry points and navigation

- `entry/src/main/ets/product/entryability/EntryAbility.ets`: app lifecycle, window management, handles PDF file URIs from system intents.
- `entry/src/main/ets/product/pages/Index.ets`: file picker landing page; routes to PDFView with sandbox file path.
- `entry/src/main/ets/features/viewer/PDFView.ets`: viewer shell. It already far exceeds the page-shell budget — compose and extract; do not grow it.

### Data flow

1. Files are copied from system URI to sandbox (`tempDir`) before loading via `DocumentOpenService`.
2. `PageStore` manages pages with lazy thumbnail/cache loading (`IDataSource`).
3. Page rendering uses `@kit.PDFKit` `pdfService` with multi-scale PixelMap caching via `PdfRenderSession` / `PdfRenderWorker` (custom path, not system `PdfView`).
4. Strokes are stored per-page in `PageInfo.strokes[]` and rendered via Canvas overlay.

### Memory management

- Call `evictAllViewerCaches()` / thumbnail release when pages scroll out of view.
- Use `prefetchPagesAround(centerIndex, prefetchRange, evictionRange, displayedPageIndices)` for smart caching.
- Honor `onMemoryLevel` → `PageStore.applyMemoryPressure`.

## Agent-friendly coding rules

1. **Ownership**: change files inside the owning folder. Put new viewer logic in a controller or sibling under `features/viewer/`, not into `PDFView.ets`. Extract from `PDFView.ets` only when the current change already has to touch it — do not split it in unrelated PRs.
2. **File budget**: prefer under ~800 lines for new page shells; under ~1200 for controllers; split when exceeded. `PDFView.ets` is already ~4000 lines; that is known debt, not a license to grow it.
3. **No new AppStorage string keys** outside `common/session/AppSession`. Known exception: `features/continuation/PdfContinuation.ets` already owns `justpdfContinueSandboxPath`, `justpdfContinueSystemPath`, `justpdfContinueFileName`, `justpdfContinuePageIndex`. New keys still go in AppSession; do not open a third place.
4. **Controllers take narrow interfaces** (`StrokeStore`, `DocumentIO`, `PageNavigator`) — not large closure bags over `@Local`.
5. **Inline** one-line / single-caller thin wrappers; keep real FSMs as named classes.
6. **Side effects stay in one place per concern** (e.g. page-turn commit only in the page-turn controller).
7. **Verify** with `.\check.ps1` then `.\build.ps1` after structural changes; for API questions use `devecocli docs search/read` or local docs. For on-device UI use `.\ui-inspect.ps1` / `devecocli ui`.
8. **Skills**: official HarmonyOS skills live in `.agents/skills`. Do not reinstall them under `.cursor/skills`. Keep JustPDF-only skills (`bump-app-version`, `commit-batcher`, `deveco-create-project`, `plan-*`) here too. Refresh with `devecocli skills add --skill <name> --path .agents/skills -f`.
   - CLI / language / UI: `deveco-cli`, `hmos-arkui-develop-skill`, `hmos-arkui-knowledge-retriever`, `hmos-arkts-knowledge-retriever`, `hmos-arkts-syntax-checker`
   - Runtime / memory: `hmos-runtime-fix-skill`, `hmos-jscrash-analysis`, `hmos-jsleak-analysis`, `hmos-memleak-analysis`
   - Multi-device / stylus / orientation: `hmos-multidevice-scenario-entry`, `hmos-multidevice-screen-window-size`, `hmos-multidevice-avoid-areas`, `hmos-multidevice-fold-state`, `hmos-multidevice-natural-orientation`, `hmos-multidevice-hardware-access`, `hmos-multidevice-interaction-methods`
   - App continuity / Kit APIs: `hmos-app-continuity-skill`, `hmos-one-sdk-skill`
   - Tests: `hmos-local-test`, `hmos-instrument-test`
9. Naming: use `PageStore` (not `PageInfoDataSource`).

## Manual regression checklist

Smoke these after each refactor round. Do not substitute the test scaffolds.

1. Open PDF from Index picker and from recent list.
2. Open PDF via system Want / share into the app (cold and warm while viewer active).
3. Password-protected PDF: correct password loads; cancel leaves cleanly.
4. Horizontal slide page-turn (commit + cancel) in 1/2/3-column modes.
5. Pan/zoom; stylus annotate draw/erase; undo/redo; save; leave with unsaved prompt.
6. Bookmark panel + floating metronome/tuner/annotation palette dock/float/scale.
7. Cross-device continuation migrate/restore (if hardware available).
8. Memory pressure path does not crash (scroll far + background).
9. Share / export from viewer still works.
10. Switching a device from debug to release (or the reverse): uninstall first, then install.
