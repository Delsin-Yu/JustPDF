import { AbilityConstant, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  clearPdfContinuationSnapshot,
  getPdfContinuationSnapshot,
  logPdfContinuationSnapshot,
  setPdfContinuationSnapshot
} from './PdfContinuationSession';

/** 接续相关日志统一 TAG，便于 hilog 过滤：-T JustPDFContinue */
export const CONTINUE_LOG_TAG: string = 'JustPDFContinue';

/** want 参数键：与系统保留字段 version / targetDevice / data / sessionId 区分 */
export const CONTINUE_WANT_FILE_REF: string = 'justpdf_fileRef';
export const CONTINUE_WANT_PAGE_INDEX: string = 'justpdf_pageIndex';
export const CONTINUE_WANT_FILE_NAME: string = 'justpdf_fileName';

/** AppStorage：源端 onContinue 读取当前阅读状态 */
export const CONTINUE_SANDBOX_PATH_KEY: string = 'justpdfContinueSandboxPath';
export const CONTINUE_SYSTEM_PATH_KEY: string = 'justpdfContinueSystemPath';
export const CONTINUE_FILE_NAME_KEY: string = 'justpdfContinueFileName';
export const CONTINUE_PAGE_INDEX_KEY: string = 'justpdfContinuePageIndex';

/** 路由参数：目的端打开 PDF 后跳转页 */
export const ROUTER_INITIAL_PAGE_INDEX: string = 'initialPageIndex';

export interface PdfContinuationPayload {
  fileRef: string;
  pageIndex: number;
  fileName: string;
}

export interface PdfContinuationReadingState {
  sandboxPath: string;
  systemPath: string;
  fileName: string;
  pageIndex: number;
}

export function describeLaunchReason(launchParam: AbilityConstant.LaunchParam): string {
  const reason = launchParam.launchReason;
  if (reason === AbilityConstant.LaunchReason.CONTINUATION) {
    return `CONTINUATION(${reason})`;
  }
  if (reason === AbilityConstant.LaunchReason.START_ABILITY) {
    return `START_ABILITY(${reason})`;
  }
  return `OTHER(${reason})`;
}

export function logContinuationLine(message: string): void {
  hilog.info(0x0000, CONTINUE_LOG_TAG, `[接续] ${message}`);
}

export function logContinuationWarn(message: string): void {
  hilog.warn(0x0000, CONTINUE_LOG_TAG, `[接续] ${message}`);
}

export function logContinuationError(message: string): void {
  hilog.error(0x0000, CONTINUE_LOG_TAG, `[接续] ${message}`);
}

export function logWantParameterKeys(want: Want, label: string): void {
  const params = want.parameters;
  if (params === undefined) {
    logContinuationLine(`${label}: want.parameters=undefined`);
    return;
  }
  const keys = Object.keys(params);
  logContinuationLine(`${label}: want.parameters 键数量=${keys.length}, keys=[${keys.join(', ')}]`);
  const version = params['version'];
  const targetDevice = params['targetDevice'];
  if (version !== undefined) {
    logContinuationLine(`${label}: 系统字段 version=${String(version)}`);
  }
  if (targetDevice !== undefined) {
    logContinuationLine(`${label}: 系统字段 targetDevice=${String(targetDevice)}`);
  }
}

export function logAppStorageContinuationState(label: string): void {
  const hasSandbox = AppStorage.has(CONTINUE_SANDBOX_PATH_KEY);
  const sandboxPath = AppStorage.get<string>(CONTINUE_SANDBOX_PATH_KEY) ?? '';
  const systemPath = AppStorage.get<string>(CONTINUE_SYSTEM_PATH_KEY) ?? '';
  const fileName = AppStorage.get<string>(CONTINUE_FILE_NAME_KEY) ?? '';
  const pageIndex = AppStorage.get<number>(CONTINUE_PAGE_INDEX_KEY) ?? -1;
  logContinuationLine(
    `${label}: AppStorage hasSandbox=${hasSandbox}, pageIndex=${pageIndex}, fileName=${fileName}, ` +
    `sandboxLen=${sandboxPath.length}, systemLen=${systemPath.length}`
  );
  if (sandboxPath.length > 0) {
    logContinuationLine(`${label}: sandboxPath=${sandboxPath}`);
  }
  if (systemPath.length > 0) {
    logContinuationLine(`${label}: systemPath=${systemPath}`);
  }
}

export function updateContinuationReadingState(
  sandboxPath: string,
  systemPath: string,
  fileName: string,
  pageIndex: number
): void {
  if (sandboxPath.length === 0) {
    logContinuationWarn('updateContinuationReadingState 跳过：sandboxPath 为空');
    return;
  }
  AppStorage.setOrCreate(CONTINUE_SANDBOX_PATH_KEY, sandboxPath);
  AppStorage.setOrCreate(CONTINUE_SYSTEM_PATH_KEY, systemPath);
  AppStorage.setOrCreate(CONTINUE_FILE_NAME_KEY, fileName);
  AppStorage.setOrCreate(CONTINUE_PAGE_INDEX_KEY, pageIndex);
  setPdfContinuationSnapshot({
    sandboxPath: sandboxPath,
    systemPath: systemPath,
    fileName: fileName,
    pageIndex: pageIndex
  });
}

export function clearContinuationReadingState(): void {
  logContinuationLine('clearContinuationReadingState（离开阅读页）');
  AppStorage.delete(CONTINUE_SANDBOX_PATH_KEY);
  AppStorage.delete(CONTINUE_SYSTEM_PATH_KEY);
  AppStorage.delete(CONTINUE_FILE_NAME_KEY);
  AppStorage.delete(CONTINUE_PAGE_INDEX_KEY);
  clearPdfContinuationSnapshot();
}

/** onContinue 优先读进程内 Session，避免 aboutToDisappear 先清空 AppStorage */
export function getContinuationReadingStateForMigrate(): PdfContinuationReadingState | null {
  logPdfContinuationSnapshot('getContinuationReadingStateForMigrate');
  logAppStorageContinuationState('getContinuationReadingStateForMigrate');

  const session = getPdfContinuationSnapshot();
  if (session !== undefined) {
    logContinuationLine('getContinuationReadingStateForMigrate 使用 Session 快照');
    return session;
  }

  const sandboxPath = AppStorage.get<string>(CONTINUE_SANDBOX_PATH_KEY) ?? '';
  if (sandboxPath.length === 0) {
    logContinuationWarn('getContinuationReadingStateForMigrate 无 Session 且无 AppStorage');
    return null;
  }
  logContinuationLine('getContinuationReadingStateForMigrate 回退到 AppStorage');
  return {
    sandboxPath: sandboxPath,
    systemPath: AppStorage.get<string>(CONTINUE_SYSTEM_PATH_KEY) ?? '',
    fileName: AppStorage.get<string>(CONTINUE_FILE_NAME_KEY) ?? 'document.pdf',
    pageIndex: AppStorage.get<number>(CONTINUE_PAGE_INDEX_KEY) ?? 0
  };
}

/** want 中可能携带的 DLP 沙箱路径等额外本地路径 */
export function extractContinuationExtraLocalPaths(want: Want): string[] {
  const paths: string[] = [];
  const params = want.parameters;
  if (params === undefined) {
    return paths;
  }
  const dlpSandbox = params['ohos.dlp.params.sandbox'];
  if (typeof dlpSandbox === 'string' && dlpSandbox.length > 1 && dlpSandbox.startsWith('/')) {
    paths.push(dlpSandbox);
    logContinuationLine(`extractContinuationExtraLocalPaths dlp.sandbox=${dlpSandbox}`);
  }
  return paths;
}

export function extractContinuationPayload(want: Want): PdfContinuationPayload | null {
  logWantParameterKeys(want, 'extractContinuationPayload');
  const params = want.parameters;
  if (params === undefined) {
    logContinuationError('extractContinuationPayload 失败：want.parameters 为 undefined');
    return null;
  }
  const fileRefRaw = params[CONTINUE_WANT_FILE_REF];
  if (fileRefRaw === undefined || fileRefRaw === null) {
    logContinuationError(`extractContinuationPayload 失败：缺少键 ${CONTINUE_WANT_FILE_REF}`);
    return null;
  }
  const fileRef = String(fileRefRaw);
  if (fileRef.length === 0) {
    logContinuationError(`extractContinuationPayload 失败：${CONTINUE_WANT_FILE_REF} 为空字符串`);
    return null;
  }
  let pageIndex = 0;
  const pageRaw = params[CONTINUE_WANT_PAGE_INDEX];
  if (typeof pageRaw === 'number') {
    pageIndex = Math.max(0, Math.floor(pageRaw));
  } else if (pageRaw !== undefined && pageRaw !== null) {
    const parsed = parseInt(String(pageRaw), 10);
    if (!Number.isNaN(parsed)) {
      pageIndex = Math.max(0, parsed);
    } else {
      logContinuationWarn(`pageIndex 无法解析: raw=${String(pageRaw)}，使用 0`);
    }
  } else {
    logContinuationWarn(`缺少键 ${CONTINUE_WANT_PAGE_INDEX}，使用 pageIndex=0`);
  }
  let fileName = '';
  const fileNameRaw = params[CONTINUE_WANT_FILE_NAME];
  if (fileNameRaw !== undefined && fileNameRaw !== null) {
    fileName = String(fileNameRaw);
  } else {
    const tail = fileRef.split('/').pop() ?? '';
    fileName = decodeURIComponent(tail);
  }
  logContinuationLine(
    `extractContinuationPayload 成功: fileRef=${fileRef}, pageIndex=${pageIndex}, fileName=${fileName}`
  );
  return { fileRef: fileRef, pageIndex: pageIndex, fileName: fileName };
}

export function parseInitialPageIndexFromRouter(args: Record<string, string>): number {
  const raw = args[ROUTER_INITIAL_PAGE_INDEX];
  if (raw === undefined || raw === null || raw === '') {
    logContinuationLine('路由无 initialPageIndex，从第 0 页开始');
    return 0;
  }
  const parsed = parseInt(raw, 10);
  if (Number.isNaN(parsed) || parsed < 0) {
    logContinuationWarn(`路由 initialPageIndex 无效: raw=${raw}，从第 0 页开始`);
    return 0;
  }
  logContinuationLine(`路由 initialPageIndex=${parsed}`);
  return parsed;
}
