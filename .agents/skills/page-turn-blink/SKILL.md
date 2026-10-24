---
name: page-turn-blink
description: >-
  Diagnose and fix JustPDF viewer blinks/flashes during page-turn: half-page
  overlay, horizontal-slide neighbor strips, or any cover that hides while the
  main slot swaps. Use when the user reports 闪屏, blink, flash, previous page
  then new, overlay vanishes too early, main jumps before cover appears, or
  settle flicker after swipe/half-page.
---

# JustPDF page-turn blink

Load this skill before changing half-page overlay, slide neighbor strips, or
any cover that hides while the main `Image` changes. Runtime proof is `hilog`
on device, not localhost ingest (see AGENTS.md Diagnostics).

## What the user sees

- After a swipe or half-step, the **previous page** (or a white/placeholder)
  flashes, then the destination.
- Finger starts a **backward** half-step and the **main slot jumps first**;
  the same-content cover appears later.
- Forward half-step looks fine; backward still blinks (or the reverse).

The cover and the main slot are two `Image` nodes. ArkUI paints them
asynchronously. JS state `shown=true` / `applyCache` is **not** on-screen yet.

## Required order

Keep this sequence. Do not invert it.

1. **Show the cover** with the **same pixels the user already sees**
   (`reveal=1` / strip locked at center, opacity 1).
2. Wait until that cover has **painted** (`displaySync` ≥ 2 frames after the
   node is already mounted — not after a `Hidden`→`Visible` remount).
3. **Then** change the main slot (`gotoPage` / `prime` / seed / raster).
4. Wait until the **destination** main `Image` has painted
   (`displaySync` ≥ 2 frames **after** `applyRaster` of the new page).
5. **Then** shrink or hide the cover.

`prime` / `peekPageCache` / `mainSlotReadyPage = index` only means JS copied a
`PixelMap`. It does **not** mean the `Image` composited. Do not release a hold
from those flags.

## Confirmed failure modes

| Pattern | What happens | Fix |
|---|---|---|
| Hide in the same turn as raster | `settleCover` / `clearPreview` / `clearHorizontalSlidePreviewState` runs in the same millisecond as `applyRasterCacheToSlot` | Hide only after destination raster **and** 2 paint frames |
| Swap main before cover paints | Backward half-page: `prime`/`goto` at first `p≥0.1`; overlay still `Hidden` or opacity 0 from last land | Cover first; gate the swap on `coverReady` |
| `Hidden` / `None` remount | `clearPreview` sets `overlayShown=false` → `Visibility.Hidden`; next swipe remounts `Image`. 2 frames is not enough | Keep the node `Visible` while `pixelMap` exists; hide with **opacity 0** |
| Wait frames **before** load | Slide teardown waits 2 frames, then `flush` + uncover in one turn | Wait **after** main has the destination bitmap |
| HQ/layout restore on a new gap | `endInteractiveMotionDemote` → `updateDisplayedPagesAtScale` hits the just-uncovered pixels | Skip that restore while a cover still shows, or until after uncover + paint |

Proven half-page APIs (do not replace with `Hidden` teardown):

- `PDFHalfPageController.settleFullPageCover()` — land 0.5→1: keep node, `overlayCoverOpacity=0`
- `PDFHalfPageController.parkInvisibleCoverFromMain()` — land on a full page: copy main, `reveal=1`, opacity 0
- `PDFHalfPageOverlay` — `.visibility(pixelMap ? Visible : Hidden)` and `.opacity(shown ? coverOpacity : 0)`
- `PDFView.scheduleHalfOverlayHideAfterPaint()` — 2 `displaySync` frames after main ready and `reveal≥0.99`

## Analog for normal horizontal slide

`PDFPageTurnController.uncoverAfterMainReady` currently:

1. `await flushPendingSlideMainLoad()` (main raster)
2. `clearHorizontalSlidePreviewState()` (strips → `indices=[]` → `Visibility.None`)
3. `onSlideSessionIdle` → `endInteractiveMotionDemote` (HQ swap)

That is the same “uncover in the same turn as raster” bug. Neighbor rows already
stay in the tree; emptying `transNextIndices` / `transPrevIndices` still flips
them to `Visibility.None` and drops the cover. Treat the locked preview strip
like the half-page overlay: keep it up until the seeded main `Image` has
painted, then tear down; do not HQ-restore in that same turn.

## Diagnostics

- Tag: `hilog.info(0, 'DBG-justpdf', 'slideBlink|…')` or `blink|…`
- Dump: `hdc -t <device> shell "hilog -x -T DBG-justpdf"`
- Log **order**, not just flags: `fadeDefer` / `uncoverAfterFlush` / `mainRaster0` / `demoteRestore` / `clearPreview`
- If `uncover*` and `mainRaster0` share the same millisecond, the cover is too early
- If `midSwap` / `goto` happens while `shown=false` or `op=0` and the overlay
  was `Hidden` last frame, the main jump is visible

## Do not

- Use `setTimeout` / sleep as the fix (project debug rule). Use `displaySync` or
  a paint/ready signal.
- Trust `ready===target` set by `primeMainWithPage` to release a cover hold.
- Grow `PDFView.ets` for new blink logic — put FSMs on
  `PDFHalfPageController` / `PDFPageTurnController`.
- “Fix” a blink by suppressing the destination raster so the old page stays
  under a shrinking cover (user sees the previous page in the gap).
