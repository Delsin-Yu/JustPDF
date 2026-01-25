# JustPDF - Copilot Instructions

## Project Overview
JustPDF is a HarmonyOS PDF reader app built with ArkTS/ArkUI, targeting phones, tablets, and 2-in-1 devices. It's designed for musicians with features like multi-page display modes, annotation/drawing, and page turner support.

## Architecture

### Entry Points & Navigation
- **EntryAbility** (`entry/src/main/ets/entryability/EntryAbility.ets`): App lifecycle, window management, handles PDF file URIs from system intents
- **Index page** (`entry/src/main/ets/pages/Index.ets`): File picker landing page, routes to PDFView with sandbox file path
- **PDFView page** (`entry/src/main/ets/pages/PDFView.ets`): Main PDF viewer (~1700 lines), handles rendering, gestures, annotations

### Component Structure
```
entry/src/main/ets/
├── components/
│   ├── PageInfo.ets       # PageInfo, PageGroup, PageInfoDataSource - PDF page data models with async caching
│   ├── UIComponents.ets   # Reusable styled buttons, layout constants, alignment rules
│   ├── Numbers.ets        # Vector2 math utilities, px/vp conversions
│   ├── Input.ets          # InputAction for keyboard hotkey handling
│   ├── Colletions.ets     # Generic Stack<T> implementation
│   ├── PageManagerDialog.ets  # Page thumbnail grid with drag-to-reorder
│   └── TutorialDialog.ets     # In-app tutorial content
├── pages/
│   ├── Index.ets          # File selection entry
│   └── PDFView.ets        # Main viewer with all interaction logic
└── entryability/
    └── EntryAbility.ets   # UIAbility lifecycle
```

### Data Flow Pattern
1. Files are copied from system URI to sandbox (`tempDir`) before loading
2. `PageInfoDataSource` manages `PageGroup[]` containing `PageInfo[]` with lazy thumbnail/cache loading
3. Page rendering uses `@kit.PDFKit` with multi-scale caching (4x base, 8x for zoom)
4. Strokes are stored per-page in `PageInfo.strokes[]` and rendered via Canvas overlay

## Code Conventions

### Programming Language
ArkUI uses ArkTS, a super-set of TypeScript with **ALL** untyped features turned off. Follow TypeScript best practices, including strict typing, interfaces, and async/await for asynchronous code.

### Syntax Error Handling
In VisualStudio Code with the OpenHarmony extension, it is possible that syntax errors occured where the code compiles and runs correctly in DevEco Studio (as we are targeting HarmonyOS and not OpenHarmony). So when checking for syntax errors, assueme the reported errors at the start of the agent sessions are false positives (e.g. missing apis for UI compomnents).

### Language
- UI text and comments are in **Chinese** (Simplified)
- Variable/function names in English

### Error Handling
- Use `hilog` for logging: `hilog.info(0, 'PDFView', 'message')`
- Wrap async operations in try-catch, show `AlertDialog` for user-facing errors

### Memory Management
- Call `evictViewerCache()` / `evictThumbnail()` when pages scroll out of view
- Use `prefetchPagesAround(centerIndex, prefetchRange, evictionRange)` for smart caching
