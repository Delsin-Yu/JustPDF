import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { hasUnsavedDocumentChanges } from '../ui/UnsavedChangesPrompt';
/** 启动/阅读会话在 AppStorage 中的键（新键只允许加在本文件）。 */
export const APP_SESSION_LAUNCH_URI_KEY: string = 'launchUri';
export const APP_SESSION_WINDOW_KEY: string = 'window';
export const APP_SESSION_PREFERENCES_KEY: string = 'preferences';
export const APP_SESSION_AVOID_AREA_TOP_PX_KEY: string = 'avoidAreaTopPx';
export const APP_SESSION_AVOID_AREA_BOTTOM_PX_KEY: string = 'avoidAreaBottomPx';
export const APP_SESSION_INITIAL_PDF_VIEW_ARGS_KEY: string = 'initialPdfViewArgs';
export const APP_SESSION_PDF_VIEWER_ACTIVE_KEY: string = 'pdfViewerActive';
export const APP_SESSION_PDF_VIEWER_HAS_UNSAVED_KEY: string = 'pdfViewerHasUnsavedChanges';
export const APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY: string = 'pendingDocumentOpenParams';
export const APP_SESSION_EXIT_VIEWER_ON_BACK_KEY: string = 'exitViewerOnBack';

export function setSessionWindow(win: window.Window): void {
  AppStorage.setOrCreate(APP_SESSION_WINDOW_KEY, win);
}

export function getSessionWindow(): window.Window | undefined {
  return AppStorage.get<window.Window>(APP_SESSION_WINDOW_KEY);
}

export function setSessionPreferences(prefs: preferences.Preferences): void {
  AppStorage.setOrCreate(APP_SESSION_PREFERENCES_KEY, prefs);
}

export function getSessionPreferences(): preferences.Preferences | undefined {
  return AppStorage.get<preferences.Preferences>(APP_SESSION_PREFERENCES_KEY);
}

export function setAvoidAreaPx(topPx: number, bottomPx: number): void {
  AppStorage.setOrCreate(APP_SESSION_AVOID_AREA_TOP_PX_KEY, topPx);
  AppStorage.setOrCreate(APP_SESSION_AVOID_AREA_BOTTOM_PX_KEY, bottomPx);
}

export function initAvoidAreaPx(): void {
  AppStorage.setOrCreate(APP_SESSION_AVOID_AREA_TOP_PX_KEY, 0);
  AppStorage.setOrCreate(APP_SESSION_AVOID_AREA_BOTTOM_PX_KEY, 0);
}

export function setLaunchUri(uri: string): void {
  AppStorage.setOrCreate(APP_SESSION_LAUNCH_URI_KEY, uri);
}

export function peekLaunchUri(): string | undefined {
  return AppStorage.get<string>(APP_SESSION_LAUNCH_URI_KEY);
}

/** 读取 launchUri 并清空为 ''（与历史行为一致）。 */
export function takeLaunchUri(): string | undefined {
  const uri = AppStorage.get<string>(APP_SESSION_LAUNCH_URI_KEY);
  if (uri === undefined || uri.length === 0) {
    return undefined;
  }
  AppStorage.setOrCreate(APP_SESSION_LAUNCH_URI_KEY, '');
  return uri;
}

export function clearLaunchUri(): void {
  AppStorage.setOrCreate(APP_SESSION_LAUNCH_URI_KEY, '');
}

export function setInitialPdfViewArgs(args: Record<string, string>): void {
  AppStorage.setOrCreate(APP_SESSION_INITIAL_PDF_VIEW_ARGS_KEY, args);
}

export function takeInitialPdfViewArgs(): Record<string, string> | undefined {
  if (!AppStorage.has(APP_SESSION_INITIAL_PDF_VIEW_ARGS_KEY)) {
    return undefined;
  }
  const args = AppStorage.get<Record<string, string>>(APP_SESSION_INITIAL_PDF_VIEW_ARGS_KEY);
  AppStorage.delete(APP_SESSION_INITIAL_PDF_VIEW_ARGS_KEY);
  return args;
}

export function setPdfViewerActive(active: boolean): void {
  AppStorage.setOrCreate(APP_SESSION_PDF_VIEWER_ACTIVE_KEY, active);
}

export function isPdfViewerActive(): boolean {
  return AppStorage.get<boolean>(APP_SESSION_PDF_VIEWER_ACTIVE_KEY) === true;
}

export function setExitViewerOnBack(exitOnBack: boolean): void {
  AppStorage.setOrCreate(APP_SESSION_EXIT_VIEWER_ON_BACK_KEY, exitOnBack);
}

export function shouldExitViewerOnBack(): boolean {
  return AppStorage.get<boolean>(APP_SESSION_EXIT_VIEWER_ON_BACK_KEY) === true;
}

export function syncPdfViewerHasUnsavedChanges(hasUnsavedStrokes: boolean, bookmarksDirty: boolean): void {
  AppStorage.setOrCreate(
    APP_SESSION_PDF_VIEWER_HAS_UNSAVED_KEY,
    hasUnsavedDocumentChanges(hasUnsavedStrokes, bookmarksDirty)
  );
}

export function isPdfViewerActiveWithUnsaved(): boolean {
  return isPdfViewerActive()
    && AppStorage.get<boolean>(APP_SESSION_PDF_VIEWER_HAS_UNSAVED_KEY) === true;
}

export function stashPendingDocumentOpenParams(params: Record<string, string>): void {
  AppStorage.setOrCreate(APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY, params);
}

export function takePendingDocumentOpenParams(): Record<string, string> | undefined {
  if (!AppStorage.has(APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY)) {
    return undefined;
  }
  const params = AppStorage.get<Record<string, string>>(APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY);
  AppStorage.delete(APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY);
  return params;
}
