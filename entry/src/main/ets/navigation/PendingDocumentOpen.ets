import { common } from '@kit.AbilityKit';
import { Router } from '@kit.ArkUI';
import { isContinuationPendingRouterArgs } from '../features/continuation/PdfContinuationRestore';
import {
  APP_SESSION_EXIT_VIEWER_ON_BACK_KEY,
  APP_SESSION_PDF_VIEWER_ACTIVE_KEY,
  APP_SESSION_PDF_VIEWER_HAS_UNSAVED_KEY,
  APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY,
  isPdfViewerActiveWithUnsaved as isPdfViewerActiveWithUnsavedSession,
  setExitViewerOnBack as setExitViewerOnBackSession,
  setPdfViewerActive as setPdfViewerActiveSession,
  shouldExitViewerOnBack as shouldExitViewerOnBackSession,
  stashPendingDocumentOpenParams as stashPendingDocumentOpenParamsSession,
  syncPdfViewerHasUnsavedChanges as syncPdfViewerHasUnsavedChangesSession,
  takePendingDocumentOpenParams as takePendingDocumentOpenParamsSession
} from '../common/session/AppSession';
/** @deprecated 使用 AppSession 常量；保留导出以兼容既有 import。 */
export const PDF_VIEWER_ACTIVE_KEY: string = APP_SESSION_PDF_VIEWER_ACTIVE_KEY;
export const PDF_VIEWER_HAS_UNSAVED_KEY: string = APP_SESSION_PDF_VIEWER_HAS_UNSAVED_KEY;
export const PENDING_DOCUMENT_OPEN_PARAMS_KEY: string = APP_SESSION_PENDING_DOCUMENT_OPEN_PARAMS_KEY;
export const EXIT_VIEWER_ON_BACK_KEY: string = APP_SESSION_EXIT_VIEWER_ON_BACK_KEY;

export const EVENT_DOCUMENT_OPEN_REQUESTED: string = 'documentOpenRequested';
export const EVENT_APP_TERMINATE_REQUESTED: string = 'appTerminateRequested';

const PDF_VIEW_PAGE_URL: string = 'features/viewer/PDFView';

export function setPdfViewerActive(active: boolean): void {
  setPdfViewerActiveSession(active);
}

export function setExitViewerOnBack(exitOnBack: boolean): void {
  setExitViewerOnBackSession(exitOnBack);
}

export function shouldExitViewerOnBack(): boolean {
  return shouldExitViewerOnBackSession();
}

export function syncPdfViewerHasUnsavedChanges(hasUnsavedStrokes: boolean, bookmarksDirty: boolean): void {
  syncPdfViewerHasUnsavedChangesSession(hasUnsavedStrokes, bookmarksDirty);
}

export function isPdfViewerActiveWithUnsaved(): boolean {
  return isPdfViewerActiveWithUnsavedSession();
}

/** 普通打开需 sandboxPath；接续打开 sandbox 为空、由 PDFView 内落地。 */
export function isValidPendingDocumentOpenParams(params: Record<string, string>): boolean {
  if (isContinuationPendingRouterArgs(params)) {
    const systemPath = params['systemPath'];
    return systemPath !== undefined && systemPath.length > 0;
  }
  const sandboxPath = params['sandboxPath'];
  return sandboxPath !== undefined && sandboxPath.length > 0;
}

export function stashPendingDocumentOpenParams(params: Record<string, string>): void {
  stashPendingDocumentOpenParamsSession(params);
}

export function takePendingDocumentOpenParams(): Record<string, string> | undefined {
  return takePendingDocumentOpenParamsSession();
}

/**
 * 在阅读页有未保存更改时暂存并通知 PDFView 弹窗；否则直接 replaceUrl。
 * @returns 是否已处理（含已 defer 到 PDFView）
 */
export function requestReplacePdfDocument(
  abilityContext: common.UIAbilityContext,
  router: Router | undefined,
  args: Record<string, string>
): boolean {
  if (!isValidPendingDocumentOpenParams(args)) {
    return false;
  }
  if (isPdfViewerActiveWithUnsaved()) {
    stashPendingDocumentOpenParams(args);
    abilityContext.eventHub.emit(EVENT_DOCUMENT_OPEN_REQUESTED);
    return true;
  }
  if (router === undefined) {
    return false;
  }
  router.replaceUrl({ url: PDF_VIEW_PAGE_URL, params: args }).catch(() => {
  });
  return true;
}
