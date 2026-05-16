import { hilog } from '@kit.PerformanceAnalysisKit';
import { CONTINUE_LOG_TAG } from './PdfContinuation';

function logSessionLine(message: string): void {
  hilog.info(0x0000, CONTINUE_LOG_TAG, `[接续] ${message}`);
}

function logSessionWarn(message: string): void {
  hilog.warn(0x0000, CONTINUE_LOG_TAG, `[接续] ${message}`);
}

/** 进程内接续快照：onContinue 在 UIAbility 中执行，不能依赖可能被 aboutToDisappear 清空的 AppStorage */
export interface PdfContinuationReadingSnapshot {
  sandboxPath: string;
  systemPath: string;
  fileName: string;
  pageIndex: number;
}

let activeSnapshot: PdfContinuationReadingSnapshot | undefined = undefined;

export function setPdfContinuationSnapshot(snapshot: PdfContinuationReadingSnapshot): void {
  activeSnapshot = {
    sandboxPath: snapshot.sandboxPath,
    systemPath: snapshot.systemPath,
    fileName: snapshot.fileName,
    pageIndex: snapshot.pageIndex
  };
  logSessionLine(
    `Session.set pageIndex=${snapshot.pageIndex}, fileName=${snapshot.fileName}, sandboxLen=${snapshot.sandboxPath.length}`
  );
}

export function getPdfContinuationSnapshot(): PdfContinuationReadingSnapshot | undefined {
  if (activeSnapshot === undefined || activeSnapshot.sandboxPath.length === 0) {
    return undefined;
  }
  return {
    sandboxPath: activeSnapshot.sandboxPath,
    systemPath: activeSnapshot.systemPath,
    fileName: activeSnapshot.fileName,
    pageIndex: activeSnapshot.pageIndex
  };
}

export function clearPdfContinuationSnapshot(): void {
  if (activeSnapshot !== undefined) {
    logSessionLine('Session.clear');
  }
  activeSnapshot = undefined;
}

export function logPdfContinuationSnapshot(label: string): void {
  const snap = getPdfContinuationSnapshot();
  if (snap === undefined) {
    logSessionWarn(`${label}: Session 无有效快照`);
    return;
  }
  logSessionLine(
    `${label}: Session pageIndex=${snap.pageIndex}, fileName=${snap.fileName}, sandbox=${snap.sandboxPath}`
  );
}
