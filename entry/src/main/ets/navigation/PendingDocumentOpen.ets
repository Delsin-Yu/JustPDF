import { common } from '@kit.AbilityKit';
import { Router } from '@kit.ArkUI';
import { hasUnsavedDocumentChanges } from '../components/UnsavedChangesPrompt';
import { isContinuationPendingRouterArgs } from '../continuation/PdfContinuationRestore';

export const PDF_VIEWER_ACTIVE_KEY: string = 'pdfViewerActive';
export const PDF_VIEWER_HAS_UNSAVED_KEY: string = 'pdfViewerHasUnsavedChanges';
export const PENDING_DOCUMENT_OPEN_PARAMS_KEY: string = 'pendingDocumentOpenParams';
/** 由系统 Want（打开/分享 PDF）进入阅读页时为 true：返回应移到后台回到调用方（不销毁 Ability）。 */
export const EXIT_VIEWER_ON_BACK_KEY: string = 'exitViewerOnBack';

export const EVENT_DOCUMENT_OPEN_REQUESTED: string = 'documentOpenRequested';
export const EVENT_APP_TERMINATE_REQUESTED: string = 'appTerminateRequested';

const PDF_VIEW_PAGE_URL: string = 'pages/PDFView';

export function setPdfViewerActive(active: boolean): void {
  AppStorage.setOrCreate(PDF_VIEWER_ACTIVE_KEY, active);
}

export function setExitViewerOnBack(exitOnBack: boolean): void {
  AppStorage.setOrCreate(EXIT_VIEWER_ON_BACK_KEY, exitOnBack);
}

export function shouldExitViewerOnBack(): boolean {
  return AppStorage.get<boolean>(EXIT_VIEWER_ON_BACK_KEY) === true;
}

export function syncPdfViewerHasUnsavedChanges(hasUnsavedStrokes: boolean, bookmarksDirty: boolean): void {
  AppStorage.setOrCreate(PDF_VIEWER_HAS_UNSAVED_KEY, hasUnsavedDocumentChanges(hasUnsavedStrokes, bookmarksDirty));
}

export function isPdfViewerActiveWithUnsaved(): boolean {
  return AppStorage.get<boolean>(PDF_VIEWER_ACTIVE_KEY) === true
    && AppStorage.get<boolean>(PDF_VIEWER_HAS_UNSAVED_KEY) === true;
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
  AppStorage.setOrCreate(PENDING_DOCUMENT_OPEN_PARAMS_KEY, params);
}

export function takePendingDocumentOpenParams(): Record<string, string> | undefined {
  if (!AppStorage.has(PENDING_DOCUMENT_OPEN_PARAMS_KEY)) {
    return undefined;
  }
  const params = AppStorage.get<Record<string, string>>(PENDING_DOCUMENT_OPEN_PARAMS_KEY);
  AppStorage.delete(PENDING_DOCUMENT_OPEN_PARAMS_KEY);
  return params;
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
  router.replaceUrl({ url: PDF_VIEW_PAGE_URL, params: args });
  return true;
}
